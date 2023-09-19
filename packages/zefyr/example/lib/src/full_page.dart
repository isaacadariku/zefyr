// Copyright (c) 2018, the Zefyr project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:example/src/url_launcher_util.dart';
import 'package:flutter/material.dart';
import 'package:zefyr/zefyr.dart';

class ZefyrLogo extends StatelessWidget {
  const ZefyrLogo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text('Ze'),
        FlutterLogo(size: 24.0),
        Text('yr'),
      ],
    );
  }
}

class FullPageEditorScreen extends StatefulWidget {
  const FullPageEditorScreen({Key? key}) : super(key: key);

  @override
  FullPageEditorScreenState createState() => FullPageEditorScreenState();
}

const doc =
    r'[{"insert":"Zefyr"},{"insert":"\n","attributes":{"heading":1}},{"insert":"Soft and gentle rich text editing for Flutter applications.","attributes":{"i":true}},{"insert":"\n"},{"insert":"​","attributes":{"embed":{"type":"image","source":"asset://images/breeze.jpg"}}},{"insert":"\n"},{"insert":"Photo by Hiroyuki Takeda.","attributes":{"i":true}},{"insert":"\nZefyr is currently in "},{"insert":"early preview","attributes":{"b":true}},{"insert":". If you have a feature request or found a bug, please file it at the "},{"insert":"issue tracker","attributes":{"a":"https://github.com/memspace/zefyr/issues"}},{"insert":'
    r'".\nDocumentation"},{"insert":"\n","attributes":{"heading":3}},{"insert":"Quick Start","attributes":{"a":"https://github.com/memspace/zefyr/blob/master/doc/quickstart.md"}},{"insert":"\n","attributes":{"block":"ul"}},{"insert":"Data Format and Document Model","attributes":{"a":"https://github.com/memspace/zefyr/blob/master/doc/data_and_document.md"}},{"insert":"\n","attributes":{"block":"ul"}},{"insert":"Style Attributes","attributes":{"a":"https://github.com/memspace/zefyr/blob/master/doc/attr'
    r'ibutes.md"}},{"insert":"\n","attributes":{"block":"ul"}},{"insert":"Heuristic Rules","attributes":{"a":"https://github.com/memspace/zefyr/blob/master/doc/heuristics.md"}},{"insert":"\n","attributes":{"block":"ul"}},{"insert":"FAQ","attributes":{"a":"https://github.com/memspace/zefyr/blob/master/doc/faq.md"}},{"insert":"\n","attributes":{"block":"ul"}},{"insert":"Clean and modern look"},{"insert":"\n","attributes":{"heading":2}},{"insert":"Zefyr’s rich text editor is built with simplicity and fle'
    r'xibility in mind. It provides clean interface for distraction-free editing. Think Medium.com-like experience.\nMarkdown inspired semantics"},{"insert":"\n","attributes":{"heading":2}},{"insert":"Ever needed to have a heading line inside of a quote block, like this:\nI’m a Markdown heading"},{"insert":"\n","attributes":{"block":"quote","heading":3}},{"insert":"And I’m a regular paragraph"},{"insert":"\n","attributes":{"block":"quote"}},{"insert":"Code blocks"},{"insert":"\n","attributes":{"headin'
    r'g":2}},{"insert":"Of course:\nimport ‘package:flutter/material.dart’;"},{"insert":"\n","attributes":{"block":"code"}},{"insert":"import ‘package:zefyr/zefyr.dart’;"},{"insert":"\n\n","attributes":{"block":"code"}},{"insert":"void main() {"},{"insert":"\n","attributes":{"block":"code"}},{"insert":" runApp(MyZefyrApp());"},{"insert":"\n","attributes":{"block":"code"}},{"insert":"}"},{"insert":"\n","attributes":{"block":"code"}},{"insert":"\n\n\n"}]';

@visibleForTesting
enum Options { darkTheme }

class FullPageEditorScreenState extends State<FullPageEditorScreen> {
  final ZefyrController _controller =
      ZefyrController(NotusDocument.fromJson(json.decode(doc)));
  final FocusNode _focusNode = FocusNode();
  bool _editing = false;
  late StreamSubscription<NotusChange> _sub;
  bool _darkTheme = false;

  @override
  void initState() {
    super.initState();
    _sub = _controller.document.changes.listen((change) {
      // ignore: avoid_print
      print('${change.source}: ${change.change}');
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _editing
        ? IconButton(onPressed: _stopEditing, icon: const Icon(Icons.save))
        : IconButton(onPressed: _startEditing, icon: const Icon(Icons.edit));
    final result = Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const ZefyrLogo(),
        actions: [
          done,
          PopupMenuButton<Options>(
            itemBuilder: buildPopupMenu,
            onSelected: handlePopupItemSelected,
          )
        ],
      ),
      body: ZefyrField(
        padding: const EdgeInsets.all(16),
        controller: _controller,
        focusNode: _focusNode,
        readOnly: !_editing,
        onLaunchUrl: openUrl,
        // keyboardAppearance: _darkTheme ? Brightness.dark : Brightness.light,
      ),
    );
    if (_darkTheme) {
      return Theme(data: ThemeData.dark(), child: result);
    }
    return Theme(data: ThemeData(primarySwatch: Colors.cyan), child: result);
  }

  void handlePopupItemSelected(value) {
    if (!mounted) return;
    setState(() {
      if (value == Options.darkTheme) {
        _darkTheme = !_darkTheme;
      }
    });
  }

  List<PopupMenuEntry<Options>> buildPopupMenu(BuildContext context) {
    return [
      CheckedPopupMenuItem(
        value: Options.darkTheme,
        checked: _darkTheme,
        child: const Text('Dark theme'),
      ),
    ];
  }

  void _startEditing() {
    setState(() {
      _editing = true;
    });
  }

  void _stopEditing() {
    setState(() {
      _editing = false;
    });
  }
}
