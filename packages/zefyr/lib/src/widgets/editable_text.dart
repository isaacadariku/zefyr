// Copyright (c) 2018, the Zefyr project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:notus/notus.dart';

import 'code.dart';
import 'common.dart';
import 'controller.dart';
import 'cursor_timer.dart';
import 'editor.dart';
import 'image.dart';
import 'input.dart';
import 'list.dart';
import 'mode.dart';
import 'paragraph.dart';
import 'quote.dart';
import 'render_context.dart';
import 'scope.dart';
import 'selection.dart';
import 'theme.dart';

/// Core widget responsible for editing Zefyr documents.
///
/// Depends on presence of [ZefyrTheme] and [ZefyrScope] somewhere up the
/// widget tree.
///
/// Consider using [ZefyrEditor] which wraps this widget and adds a toolbar to
/// edit style attributes.
class ZefyrEditableText extends StatefulWidget {
  const ZefyrEditableText({
    Key key,
    @required this.controller,
    @required this.focusNode,
    @required this.imageDelegate,
    this.selectionControls,
    this.autofocus = true,
    this.mode = ZefyrMode.edit,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0),
    this.physics,
    this.keyboardAppearance = Brightness.light,
  })  : assert(mode != null),
        assert(controller != null),
        assert(focusNode != null),
        assert(keyboardAppearance != null),
        super(key: key);

  /// Controls the document being edited.
  final ZefyrController controller;

  /// Controls whether this editor has keyboard focus.
  final FocusNode focusNode;
  final ZefyrImageDelegate imageDelegate;

  /// Whether this text field should focus itself if nothing else is already
  /// focused.
  ///
  /// If true, the keyboard will open as soon as this text field obtains focus.
  /// Otherwise, the keyboard is only shown after the user taps the text field.
  ///
  /// Defaults to true. Cannot be null.
  final bool autofocus;

  /// Editing mode of this text field.
  final ZefyrMode mode;

  /// Controls physics of scrollable text field.
  final ScrollPhysics physics;

  /// Optional delegate for building the text selection handles and toolbar.
  ///
  /// If not provided then platform-specific implementation is used by default.
  final TextSelectionControls selectionControls;

  /// Padding around editable area.
  final EdgeInsets padding;

  /// The appearance of the keyboard.
  ///
  /// This setting is only honored on iOS devices.
  ///
  /// If unset, defaults to the brightness of [Brightness.light].
  final Brightness keyboardAppearance;

  @override
  _ZefyrEditableTextState createState() => _ZefyrEditableTextState();
}

class _ZefyrEditableTextState extends State<ZefyrEditableText>
    with AutomaticKeepAliveClientMixin {
  //
  // New public members
  //

  /// Document controlled by this widget.
  NotusDocument get document => widget.controller.document;

  /// Current text selection.
  TextSelection get selection => widget.controller.selection;

  FocusNode _focusNode;
  FocusAttachment _focusAttachment;

  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  /// Express interest in interacting with the keyboard.
  ///
  /// If this control is already attached to the keyboard, this function will
  /// request that the keyboard become visible. Otherwise, this function will
  /// ask the focus system that it become focused. If successful in acquiring
  /// focus, the control will then attach to the keyboard and request that the
  /// keyboard become visible.
  void requestKeyboard() {
    if (_focusNode.hasFocus) {
      _input.openConnection(
        widget.controller.plainTextEditingValue,
        widget.keyboardAppearance,
      );
    } else {
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  void focusOrUnfocusIfNeeded() {
    if (!_didAutoFocus && widget.autofocus && widget.mode.canEdit) {
      FocusScope.of(context).autofocus(_focusNode);
      _didAutoFocus = true;
    }
    if (!widget.mode.canEdit && _focusNode.hasFocus) {
      _didAutoFocus = false;
      _focusNode.unfocus();
    }
  }

  TextSelectionControls defaultSelectionControls(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS) {
      return cupertinoTextSelectionControls;
    }
    return materialTextSelectionControls;
  }

  //
  // Overridden members of State
  //

  @override
  Widget build(BuildContext context) {
    _focusAttachment.reparent();
    super.build(context); // See AutomaticKeepAliveState.

    Widget body = ListBody(children: _buildChildren(context));

    body = SingleChildScrollView(
      controller: _scrollController,
      physics: widget.physics,
      padding: widget.padding,
      child: body,
      dragStartBehavior: DragStartBehavior.down,
    );

    final layers = <Widget>[body];
    layers.add(ZefyrSelectionOverlay(
      controls: widget.selectionControls ?? defaultSelectionControls(context),
    ));

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: Stack(fit: StackFit.expand, children: layers),
    );
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus == _hasFocus) return;
    _hasFocus = _focusNode.hasFocus;
    if (_focusNode.hasFocus) {
      RawKeyboard.instance.addListener(_onKeyEvent);
    } else {
      RawKeyboard.instance.removeListener(_onKeyEvent);
    }
  }

  void _onKeyEvent(RawKeyEvent event) {
    if (kIsWeb) return;
    if (event is! RawKeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      _onBackspace(forward: true);
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      // print(event);
      _onBackspace();
    }
  }

  void _onBackspace({bool forward = false}) {
    // print('Backspace detected!');
    final text = _input.currentTextEditingValue.text;
    assert(selection != null);
    // if (_readOnly || !selection.isValid) {
    // return;
    // }
    var textBefore = selection.textBefore(text);
    var textAfter = selection.textAfter(text);
    var cursorPosition = math.min(selection.start, selection.end);
    // If not deleting a selection, delete the next/previous character.
    if (selection.isCollapsed) {
      if (!forward && textBefore.isNotEmpty) {
        // ignore: omit_local_variable_types
        final int characterBoundary =
            // ignore: invalid_use_of_visible_for_testing_member
            RenderEditable.previousCharacter(textBefore.length, textBefore);
        textBefore = textBefore.substring(0, characterBoundary);
        cursorPosition = characterBoundary;
      }
      if (forward && textAfter.isNotEmpty) {
        // ignore: omit_local_variable_types
        // ignore: invalid_use_of_visible_for_testing_member
        final deleteCount = RenderEditable.nextCharacter(0, textAfter);
        textAfter = textAfter.substring(deleteCount);
      }
    }
    final newSelection = TextSelection.collapsed(offset: cursorPosition);
    final value = TextEditingValue(
      text: textBefore + textAfter,
      selection: newSelection,
    );
    _input.updateEditingValue(value);
    _input.updateRemoteValue(value, alwaysUpdateRemote: true);
  }

  @override
  void initState() {
    _focusNode = widget.focusNode;
    super.initState();
    _focusAttachment = _focusNode.attach(context);
    _input = InputConnectionController(_handleRemoteValueChange);
    _scrollController.addListener(_handleScrollChange);
    _updateSubscriptions();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(ZefyrEditableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode != widget.focusNode) {
      _focusAttachment.detach();
      _focusNode = widget.focusNode;
      _focusAttachment = _focusNode.attach(context);
    }
    _updateSubscriptions(oldWidget);
    focusOrUnfocusIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = ZefyrScope.of(context);
    if (_renderContext != scope.renderContext) {
      _renderContext?.removeListener(_handleRenderContextChange);
      _renderContext = scope.renderContext;
      _renderContext.addListener(_handleRenderContextChange);
    }
    if (_cursorTimer != scope.cursorTimer) {
      _cursorTimer?.stop();
      _cursorTimer = scope.cursorTimer;
      _cursorTimer.startOrStop(_focusNode, selection);
    }
    focusOrUnfocusIfNeeded();
  }

  @override
  void dispose() {
    _focusAttachment.detach();
    _cancelSubscriptions();
    _scrollController.removeListener(_handleScrollChange);
    _scrollController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  //
  // Overridden members of AutomaticKeepAliveClientMixin
  //

  @override
  bool get wantKeepAlive => _focusNode.hasFocus;

  //
  // Private members
  //

  ZefyrRenderContext _renderContext;
  CursorTimer _cursorTimer;
  InputConnectionController _input;
  bool _didAutoFocus = false;
  bool _hasFocus = false;

  List<Widget> _buildChildren(BuildContext context) {
    final result = <Widget>[];
    for (Node node in document.root.children) {
      result.add(_defaultChildBuilder(context, node));
    }
    return result;
  }

  Widget _defaultChildBuilder(BuildContext context, Node node) {
    if (node is LineNode) {
      if (node.hasEmbed) {
        return ZefyrLine(node: node);
      } else if (node.style.contains(NotusAttribute.heading)) {
        return ZefyrHeading(node: node);
      } else {
        return ZefyrParagraph(node: node);
      }
    } else {
      final BlockNode block = node;
      final blockStyle = block.style.get(NotusAttribute.block);
      if (blockStyle == NotusAttribute.block.code) {
        return ZefyrCode(node: block);
      } else if (blockStyle == NotusAttribute.block.bulletList) {
        return ZefyrList(node: block);
      } else if (blockStyle == NotusAttribute.block.numberList) {
        return ZefyrList(node: block);
      } else if (blockStyle == NotusAttribute.block.quote) {
        return ZefyrQuote(node: block);
      }

      throw UnimplementedError('Block format $blockStyle.');
    }
  }

  void _updateSubscriptions([ZefyrEditableText oldWidget]) {
    if (oldWidget == null) {
      widget.controller.addListener(_handleLocalValueChange);
      _focusNode.addListener(_handleFocusChange);
      return;
    }

    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_handleLocalValueChange);
      widget.controller.addListener(_handleLocalValueChange);
      _input.updateRemoteValue(widget.controller.plainTextEditingValue);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      widget.focusNode.addListener(_handleFocusChange);
      updateKeepAlive();
    }
  }

  void _cancelSubscriptions() {
    _renderContext.removeListener(_handleRenderContextChange);
    widget.controller.removeListener(_handleLocalValueChange);
    _focusNode.removeListener(_handleFocusChange);
    _input.closeConnection();
    _cursorTimer.stop();
  }

  // Triggered for both text and selection changes.
  void _handleLocalValueChange() {
    if (widget.mode.canEdit &&
        widget.controller.lastChangeSource == ChangeSource.local) {
      // Only request keyboard for user actions.
      requestKeyboard();
    }
    _input.updateRemoteValue(widget.controller.plainTextEditingValue);
    _cursorTimer.startOrStop(_focusNode, selection);
    setState(() {
      // nothing to update internally.
    });
  }

  void _handleFocusChange() {
    _input.openOrCloseConnection(_focusNode,
        widget.controller.plainTextEditingValue, widget.keyboardAppearance);
    _cursorTimer.startOrStop(_focusNode, selection);
    updateKeepAlive();
  }

  void _handleRemoteValueChange(
      int start, String deleted, String inserted, TextSelection selection) {
    widget.controller
        .replaceText(start, deleted.length, inserted, selection: selection);
  }

  void _handleRenderContextChange() {
    setState(() {
      // nothing to update internally.
    });
  }

  void _handleScrollChange() {
    final scrollDirection = _scrollController.position.userScrollDirection;
    if (scrollDirection == ScrollDirection.idle &&
        widget.controller.selection.isCollapsed) {
      if (widget.controller.document.length - 1 ==
          widget.controller.selection.end) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      } else {
        _scrollController.jumpTo(_scrollOffset);
      }
    } else {
      _scrollOffset = _scrollController.offset;
    }
  }
}
