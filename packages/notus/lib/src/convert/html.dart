// Copyright (c) 2018, the Zefyr project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:convert';

import 'package:quill_delta/quill_delta.dart';
import 'package:notus/notus.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';

class NotusHTMLCodec extends Codec<Delta, String> {
  const NotusHTMLCodec();

  @override
  Converter<String, Delta> get decoder => _HTMLNotusDecoder();

  @override
  Converter<Delta, String> get encoder => _NotusHTMLEncoder();
}

class Keys {
  static final line = "line";
  static final inline = "inline";
}

class DeltaKeys {
  static const ol = "ol";
  static const ul = "ul";
  static const a = "a";
  static const i = "i";
  static const b = "b";
  static const quote = "quote";
  static const code = "code";
  static const type = "type";
  static const block = "block";
  static const image = "image";
  static const imageSrc = "source";
  static const hr = "hr";
  static const insert = "insert";
  static const attributes = "attributes";
  static const heading = "heading";
  static const embed = "embed";
}

class HtmlKeys {
  static const blockquote = "blockquote";
  static const unorderedList = "ul";
  static const orderedList = "ol";
  static const list = "li";
  static const heading = "h";
  static const h1 = "h1";
  static const h2 = "h2";
  static const h3 = "h3";
  static const anchor = "a";
  static const anchorHref = "href";
  static const bold = "b";
  static const italic = "i";
  static const horizontalRule = "hr";
  static const image = "img";
  static const imageSrc = "src";
  static const br = "br";
  static const preformatted = "pre";
}

String htmlTagNameToDeltaAttributeName(String htmlTag) {
  switch (htmlTag) {
    case HtmlKeys.blockquote:
    case HtmlKeys.unorderedList:
    case HtmlKeys.orderedList:
    case HtmlKeys.preformatted:
      return DeltaKeys.block;
    case HtmlKeys.h1:
    case HtmlKeys.h2:
    case HtmlKeys.h3:
      return DeltaKeys.heading;
    case HtmlKeys.anchor:
      return DeltaKeys.a;
    case HtmlKeys.bold:
      return DeltaKeys.b;
    case HtmlKeys.italic:
      return DeltaKeys.i;
    case HtmlKeys.horizontalRule:
    case HtmlKeys.image:
      return DeltaKeys.embed;
    case HtmlKeys.br:
    case HtmlKeys.list:
    default:
      return null;
  }
}

class _NotusHTMLEncoder extends Converter<Delta, String> {
  static final kSimpleBlocks = <NotusAttribute, String>{
    NotusAttribute.bq: HtmlKeys.blockquote,
    NotusAttribute.ul: HtmlKeys.unorderedList,
    NotusAttribute.ol: HtmlKeys.orderedList,
  };
  Map<String, dynamic> container;

  String buildContainer(String key) {
    if (container == null || !container.containsKey(key)) {
      return '';
    }
    final attributes = Map<String, dynamic>.from(container[key]);
    final buffer = StringBuffer();
    int counter = 0;
    int length = attributes.length;
    buffer.write(" ");
    attributes.forEach((key, val) {
      if (val == null) {
        buffer.write(key);
      } else {
        buffer.write("$key=\"$val\"");
      }
      counter++;
      if (counter < length) {
        buffer.write(" ");
      }
    });
    return buffer.toString();
  }

  @override
  String convert(Delta input) {
    final iterator = DeltaIterator(input);
    final buffer = StringBuffer();
    final lineBuffer = StringBuffer();
    NotusAttribute<String> currentBlockStyle;
    NotusStyle currentInlineStyle = NotusStyle();
    List<String> currentBlockLines = [];

    void _handleBlock(NotusAttribute<String> blockStyle) {
      if (currentBlockLines.isEmpty) {
        return; // Empty block
      }

      if (blockStyle == null) {
        buffer.write(currentBlockLines.join('\n'));
      } else if (blockStyle == NotusAttribute.bq ||
          blockStyle == NotusAttribute.code) {
        _writeBlockTag(buffer, blockStyle, start: true);
        buffer.write(currentBlockLines.join("\n"));
        _writeBlockTag(buffer, blockStyle, close: true);
      } else {
        for (var i = 0; i < currentBlockLines.length; i++) {
          var line = currentBlockLines[i];
          if (i == 0) {
            _writeBlockTag(buffer, blockStyle, start: true);
            buffer.writeln();
          }
          buffer.write("<${HtmlKeys.list}>");
          buffer.write(line);
          buffer.write("</${HtmlKeys.list}>");
          buffer.writeln();
          if (i == currentBlockLines.length - 1) {
            _writeBlockTag(buffer, blockStyle, close: true);
          }
        }
      }
      buffer.writeln();
    }

    void _handleSpan(String text, Map<String, dynamic> attributes) {
      final style = NotusStyle.fromJson(attributes);
      currentInlineStyle =
          _writeInline(lineBuffer, text, style, currentInlineStyle);
    }

    void _handleLine(Map<String, dynamic> attributes) {
      final style = NotusStyle.fromJson(attributes);
      final lineBlock = style.get(NotusAttribute.block);
      if (lineBlock == currentBlockStyle) {
        currentBlockLines.add(_writeLine(lineBuffer.toString(), style));
      } else {
        _handleBlock(currentBlockStyle);
        currentBlockLines.clear();
        currentBlockLines.add(_writeLine(lineBuffer.toString(), style));

        currentBlockStyle = lineBlock;
      }
      lineBuffer.clear();
    }

    String removeZeroWidthSpace(String text) {
      return text.replaceAll(String.fromCharCode(8203), "");
    }

    while (iterator.hasNext) {
      final op = iterator.next();

      final lf = op.data.indexOf('\n');
//      container = getContainer(op.attributes);
      if (lf == -1) {
        _handleSpan(removeZeroWidthSpace(op.data), op.attributes);
      } else {
        StringBuffer span = StringBuffer();
        for (var i = 0; i < op.data.length; i++) {
          if (op.data.codeUnitAt(i) == 0x0A) {
            if (span.isNotEmpty) {
              // Write the span if it's not empty.
              _handleSpan(span.toString(), op.attributes);
            }
            // Close any open inline styles.
            _handleSpan('', null);
            _handleLine(op.attributes);
            span.clear();
          } else {
            span.writeCharCode(op.data.codeUnitAt(i));
          }
        }
        // Remaining span
        if (span.isNotEmpty) {
          _handleSpan(removeZeroWidthSpace(span.toString()), op.attributes);
        }
      }
      // container = null;
    }
    _handleBlock(currentBlockStyle); // Close the last block
    return buffer.toString();
  }

  String _writeLine(String text, NotusStyle style) {
    StringBuffer buffer = StringBuffer();
    if (style.contains(NotusAttribute.heading)) {
      _writeAttribute(buffer, style.get(NotusAttribute.heading));
    }

    // Write the text itself
    buffer.write(text);
    if (style.contains(NotusAttribute.heading)) {
      _writeAttribute(buffer, style.get(NotusAttribute.heading), close: true);
    }
    return buffer.toString();
  }

  String _trimRight(StringBuffer buffer) {
    String text = buffer.toString();
    if (!text.endsWith(' ')) return '';
    final result = text.trimRight();
    buffer.clear();
    buffer.write(result);
    return ' ' * (text.length - result.length);
  }

  NotusStyle _writeInline(StringBuffer buffer, String text, NotusStyle style,
      NotusStyle currentStyle) {
    // First close any current styles if needed
    for (final value in currentStyle.values.toList().reversed) {
      if (value.scope == NotusAttributeScope.line) continue;
      if (style.containsSame(value)) continue;
      final padding = _trimRight(buffer);
      _writeAttribute(buffer, value, close: true);
      if (padding.isNotEmpty) buffer.write(padding);
    }
    // Now open any new styles.
    for (final value in style.values) {
      if (value.scope == NotusAttributeScope.line) continue;
      if (currentStyle.containsSame(value)) continue;
      final originalText = text;
      text = text.trimLeft();
      final padding = ' ' * (originalText.length - text.length);
      if (padding.isNotEmpty) buffer.write(padding);
      _writeAttribute(buffer, value);
    }
    // Write the text itself
    buffer.write(text);
    return style;
  }

  void _writeAttribute(StringBuffer buffer, NotusAttribute attribute,
      {bool close = false}) {
    if (attribute == NotusAttribute.bold) {
      _writeBoldTag(buffer, close: close);
    } else if (attribute == NotusAttribute.italic) {
      _writeItalicTag(buffer, close: close);
    } else if (attribute.key == NotusAttribute.link.key) {
      _writeLinkTag(buffer, attribute, close: close);
    } else if (attribute.key == NotusAttribute.heading.key) {
      _writeHeadingTag(buffer, attribute, close: close);
    } else if (attribute.key == NotusAttribute.block.key) {
      _writeBlockTag(buffer, attribute, close: close);
    } else if (attribute.key == NotusAttribute.embed.key) {
      _writeEmbedTag(buffer, attribute, close: close);
    } else {
      throw ArgumentError('Cannot handle $attribute');
    }
  }

  void _writeEmbedTag(
      StringBuffer buffer, NotusAttribute<Map<String, dynamic>> embed,
      {bool close = false}) {
    if (embed.value[DeltaKeys.type] == DeltaKeys.image) {
      if (close) {
        return;
      }
      buffer.write(
          "<${HtmlKeys.image} ${HtmlKeys.imageSrc}=\"${embed.value["source"]}\"${buildContainer(DeltaKeys.embed)} />");
    } else if (embed.value[DeltaKeys.type] == DeltaKeys.hr) {
      if (close) {
        return;
      }
      buffer.write(
          "<${HtmlKeys.horizontalRule}${buildContainer(DeltaKeys.embed)} />");
    }
  }

  void _writeBoldTag(StringBuffer buffer, {bool close = false}) {
    if (close) {
      buffer.write('</${HtmlKeys.bold}>');
    } else {
      buffer.write("<${HtmlKeys.bold}${buildContainer(DeltaKeys.b)}>");
    }
  }

  void _writeItalicTag(StringBuffer buffer, {bool close = false}) {
    if (close) {
      buffer.write('</${HtmlKeys.italic}>');
    } else {
      buffer.write("<${HtmlKeys.italic}${buildContainer(DeltaKeys.i)}>");
    }
  }

  void _writeLinkTag(StringBuffer buffer, NotusAttribute<String> link,
      {bool close = false}) {
    if (close) {
      buffer.write('</${HtmlKeys.anchor}>');
    } else {
      buffer.write(
          '<${HtmlKeys.anchor} ${HtmlKeys.anchorHref}=\"${link.value}\"${buildContainer(DeltaKeys.a)}>');
    }
  }

  void _writeHeadingTag(StringBuffer buffer, NotusAttribute<int> heading,
      {bool close = false}) {
    var level = heading.value;
    if (close) {
      buffer.write('</${HtmlKeys.heading}$level>');
    } else {
      buffer.write(
          '<${HtmlKeys.heading}$level${buildContainer(DeltaKeys.heading)}>');
    }
  }

  void _writeBlockTag(StringBuffer buffer, NotusAttribute<String> block,
      {bool close = false, bool start = false}) {
    if (block == NotusAttribute.code) {
      if (start) {
        buffer.write('<${HtmlKeys.preformatted}${buildContainer(block.key)}>');
      } else if (close) {
        buffer.write('</${HtmlKeys.preformatted}>');
      }
    } else {
      final tag = kSimpleBlocks[block];
      if (start) {
        buffer.write("<${tag}${buildContainer(block.key)}>");
      } else if (close) {
        buffer.write("</${tag}>");
      } else {}
    }
  }
}

var _allowedHTMLTag = Set<String>.from([
  HtmlKeys.anchor,
  HtmlKeys.bold,
  HtmlKeys.unorderedList,
  HtmlKeys.orderedList,
  HtmlKeys.list,
  HtmlKeys.blockquote,
  HtmlKeys.horizontalRule,
  HtmlKeys.italic,
  HtmlKeys.h1,
  HtmlKeys.h2,
  HtmlKeys.h3,
  HtmlKeys.image,
  HtmlKeys.preformatted,
]);

void setDeltaAllowedTagForHTMLDecoder(Set<String> tagList) {
  _allowedHTMLTag = tagList;
}

bool isAllowedHTML(Element elem) {
  if (elem.localName == HtmlKeys.br && elem.children.isEmpty) {
    return true;
  }
  Queue queue = Queue<Element>();
  queue.add(elem);
  while (queue.isNotEmpty) {
    Element target = queue.removeFirst();
    if (!_allowedHTMLTag.contains(target.localName)) {
      return false;
    }
    queue.addAll(target.children);
  }
  return true;
}

bool isInlineAttribute(String tag) {
  if (tag == HtmlKeys.anchor ||
      tag == HtmlKeys.bold ||
      tag == HtmlKeys.italic ||
      tag == HtmlKeys.horizontalRule ||
      tag == HtmlKeys.image) {
    return true;
  }
  return false;
}

class _HTMLNotusDecoder extends Converter<String, Delta> {
  Map<String, Map<String, dynamic>> toDeltaAttribute(Queue<Element> elemStack) {
    var deltaAttributeInline = Map<String, dynamic>();
    var deltaAttributeLine = Map<String, dynamic>();
    for (final elem in elemStack) {
      switch (elem.localName) {
        case HtmlKeys.image:
          deltaAttributeInline[DeltaKeys.embed] = {
            DeltaKeys.type: DeltaKeys.image,
            DeltaKeys.imageSrc: elem.attributes[HtmlKeys.imageSrc],
          };
          break;
        case HtmlKeys.preformatted:
          deltaAttributeLine[DeltaKeys.block] = DeltaKeys.code;
          break;
        case HtmlKeys.blockquote:
          deltaAttributeLine[DeltaKeys.block] = DeltaKeys.quote;
          break;
        case HtmlKeys.horizontalRule:
          deltaAttributeInline[DeltaKeys.embed] = {
            DeltaKeys.type: DeltaKeys.hr
          };
          break;
        case HtmlKeys.list:
          if (elem.parent.localName == HtmlKeys.orderedList) {
            deltaAttributeLine[DeltaKeys.block] = DeltaKeys.ol;
          } else if (elem.parent.localName == HtmlKeys.unorderedList) {
            deltaAttributeLine[DeltaKeys.block] = DeltaKeys.ul;
          }
          break;
        case HtmlKeys.orderedList:
        case HtmlKeys.unorderedList:
          break;
        case HtmlKeys.h1:
        case HtmlKeys.h2:
        case HtmlKeys.h3:
          deltaAttributeLine[DeltaKeys.heading] =
              (int.parse(elem.localName[1]));
          break;
        case HtmlKeys.anchor:
          deltaAttributeInline[DeltaKeys.a] =
              elem.attributes[HtmlKeys.anchorHref];
          break;
        case HtmlKeys.bold:
        case HtmlKeys.italic:
          deltaAttributeInline[elem.localName] = true;
          break;
        case HtmlKeys.br:
          break;
        default:
          throw Exception("${elem.localName} not allowed");
      }
      final attr = Map<String, dynamic>.from(elem.attributes);
      if (elem.localName == HtmlKeys.anchor) {
        attr.remove(HtmlKeys.anchorHref);
      }
      if (elem.localName == HtmlKeys.image) {
        attr.remove(HtmlKeys.imageSrc);
      }
    }
    return Map<String, Map<String, dynamic>>.from({
      Keys.inline: deltaAttributeInline,
      Keys.line: deltaAttributeLine,
    });
  }

  List<Map<String, dynamic>> toDeltaFormatList(Element element) {
    final deltaFormatList = List<dynamic>();
    void insert(idx, String text, elemStack) {
      Map<String, Map<String, dynamic>> attrMap = toDeltaAttribute(elemStack);
      Map<String, dynamic> attrLine = attrMap[Keys.line];
      Map<String, dynamic> attrInline = attrMap[Keys.inline];
      if (text.isEmpty && attrInline.isEmpty && attrLine.isEmpty) return;
      final int originalLength = deltaFormatList.length;
      int shiftIdx() => idx + deltaFormatList.length - originalLength;
      void insertText(txt) {
        if (txt.isNotEmpty) {
          if (attrInline.isEmpty) {
            deltaFormatList.insert(
              shiftIdx(),
              {DeltaKeys.insert: txt},
            );
          } else {
            deltaFormatList.insert(shiftIdx(), {
              DeltaKeys.insert: txt,
              DeltaKeys.attributes: attrInline,
            });
          }
        } else if (attrInline.containsKey("embed")) {
          deltaFormatList.insert(shiftIdx(), {
            DeltaKeys.insert: String.fromCharCode(8203),
            DeltaKeys.attributes: attrInline,
          });
        }
        if (attrLine.isNotEmpty &&
            (txt.isNotEmpty || attrInline.containsKey("embed"))) {
          deltaFormatList.insert(shiftIdx(), {
            DeltaKeys.insert: "\n",
            DeltaKeys.attributes: attrLine,
          });
        }
      }

      if (attrLine.containsKey("block")) {
        for (final lineText in text.split("\n")) {
          insertText(lineText);
        }
      } else {
        insertText(text);
      }
    }

    final elemStack = Queue<Element>.from([element]);
    if (element.children.isEmpty) {
      if (element.localName == HtmlKeys.br) {
        insert(0, "\n", Queue<Element>());
      } else {
        insert(0, element.text, elemStack);
      }
      return List<Map<String, dynamic>>.from(deltaFormatList);
    }
    deltaFormatList.add(element);
    Map<Element, Queue<Element>> map = {element: elemStack};
    while (deltaFormatList.map((e) => e is Element).contains(true)) {
      for (int i = 0; i < deltaFormatList.length; i++) {
        final val = deltaFormatList[i];
        if ((val is Element) == false) continue;
        deltaFormatList.removeAt(i);
        Element elem = val;
        final currentElemStack = map[elem];
        int cursor = 0;
        final htmlString = elem.innerHtml;
        final int originalLength = deltaFormatList.length;
        int shiftIdx() => deltaFormatList.length - originalLength;
        for (var j = 0; j < elem.children.length; j++) {
          Element child = elem.children[j];
          int tagIdx = htmlString.indexOf(child.outerHtml, cursor);
          var intervalText = htmlString.substring(cursor, tagIdx);
          cursor = tagIdx + child.outerHtml.length;
          if ((elem.localName != HtmlKeys.orderedList &&
                  elem.localName != HtmlKeys.unorderedList) ||
              intervalText != '\n') {
            insert(i + shiftIdx(), intervalText, currentElemStack);
          }
          final Queue<Element> newElemStack = Queue.from(currentElemStack);
          newElemStack.addLast(child);
          if (child.children.isNotEmpty) {
            deltaFormatList.insert(i + shiftIdx(), child);
            map[child] = newElemStack;
          } else {
            insert(i + shiftIdx(), child.text, newElemStack);
          }
        }
        final lastInvervalText =
            htmlString.substring(cursor, htmlString.length);
        if ((elem.localName != HtmlKeys.orderedList &&
                elem.localName != HtmlKeys.unorderedList) ||
            lastInvervalText != '\n') {
          insert(i + shiftIdx(), lastInvervalText, currentElemStack);
        }
        break;
      }
    }
    return List<Map<String, dynamic>>.from(deltaFormatList);
  }

  Element getRootHTML(inputHTML) {
    final parsedHTML = parse(inputHTML);
    try {
      return parsedHTML.children[0].children[1];
    } on RangeError catch (e) {
      print(e);
      return null;
    }
  }

  @override
  Delta convert(String inputHTML) {
    Element rootHTML = getRootHTML(inputHTML);
    if (rootHTML == null || !rootHTML.hasContent()) {
      return Delta()..insert("\n");
    }
    String htmlString = rootHTML.innerHtml;
    final deltaFormatList = List<Map<String, dynamic>>();
    void addPlainTextToDeltaList(text) {
      if (text.isNotEmpty && text != String.fromCharCode(8203)) {
        if (deltaFormatList.isNotEmpty &&
            deltaFormatList[deltaFormatList.length - 1][DeltaKeys.attributes] ==
                null) {
          deltaFormatList[deltaFormatList.length - 1][DeltaKeys.insert] += text;
        } else {
          deltaFormatList.add({
            DeltaKeys.insert: text,
            DeltaKeys.attributes: null,
          });
        }
      }
    }

    int cursor = 0;
    for (Element firstLayerTag in rootHTML.children) {
      int tagIdx = htmlString.indexOf(firstLayerTag.outerHtml, cursor);
      final invervalText = htmlString.substring(cursor, tagIdx);
      addPlainTextToDeltaList(invervalText);
      cursor = tagIdx + firstLayerTag.outerHtml.length;
      if (isAllowedHTML(firstLayerTag)) {
        deltaFormatList.addAll(toDeltaFormatList(firstLayerTag));
      } else {
        addPlainTextToDeltaList(firstLayerTag.outerHtml);
      }
    }
    final lastInvervalText = htmlString.substring(cursor, htmlString.length);
    addPlainTextToDeltaList(lastInvervalText);

    removeRedundantNewLine(deltaList) {
      for (int i = 1; i < deltaList.length; i++) {
        Map<String, dynamic> prev = deltaList[i - 1];
        Map<String, dynamic> current = deltaList[i];
        String text = current[DeltaKeys.insert];
        if (text.startsWith("\n")) {
          Map<String, dynamic> attr = prev[DeltaKeys.attributes];
          if (attr != null &&
              (attr.containsKey("block") || attr.containsKey("heading"))) {
            if (text == "\n") {
              deltaList.remove(current);
            } else {
              current[DeltaKeys.insert] = text.replaceFirst("\n", "");
            }
          }
        }
      }
    }

    avoidConcatinatingPlainTextAndLineAttributes(deltaList) {
      bool isIncludeLineAttributes(Map<String, dynamic> jsonDelta) {
        if (!jsonDelta.containsKey(DeltaKeys.attributes)) {
          return false;
        }
        Map<String, dynamic> attr = jsonDelta[DeltaKeys.attributes];
        if (attr == null) {
          return false;
        }
        if (attr.containsKey(DeltaKeys.heading) ||
            attr.containsKey(DeltaKeys.quote) ||
            attr.containsKey(DeltaKeys.ol) ||
            attr.containsKey(DeltaKeys.ul)) {
          return true;
        }
        return false;
      }

      for (int i = 1; i < deltaList.length - 1; i++) {
        Map<String, dynamic> next = deltaList[i + 1];
        Map<String, dynamic> current = deltaList[i];
        Map<String, dynamic> prev = deltaList[i - 1];
        if (isIncludeLineAttributes(next) &&
            !prev[DeltaKeys.insert].endsWith('\n')) {
          current[DeltaKeys.insert] = '\n' + current[DeltaKeys.insert];
        }
      }
    }

    ensureEndWithNewLine(deltaList) {
      int lastIndex = deltaList.length - 1;
      String lastText = deltaList[lastIndex][DeltaKeys.insert];
      if (!lastText.endsWith("\n")) {
        if (deltaList[lastIndex][DeltaKeys.attributes] != null) {
          deltaList.add({DeltaKeys.insert: "\n"});
        } else {
          deltaList[lastIndex][DeltaKeys.insert] = lastText + "\n";
        }
      }
    }

    removeZeroWidthSpaceFromNonEmbed(deltaList) {
      for (Map<String, dynamic> deltaFormat in deltaList) {
        Map<String, dynamic> attr = deltaFormat[DeltaKeys.attributes];
        if (attr != null && attr.containsKey(DeltaKeys.embed)) {
          continue;
        }
        String text = deltaFormat[DeltaKeys.insert];
        text = text.replaceAll(String.fromCharCode(8203), "");
        deltaFormat[DeltaKeys.insert] = text;
      }
    }

    insertNewlineAfterConsecutiveAnchorTagWithImage(deltaList) {
      for (int i = 0; i < deltaList.length; i++) {
        Map<String, dynamic> prev = (i == 0) ? null : deltaList[i - 1];
        Map<String, dynamic> next =
            (i == deltaList.length - 1) ? null : deltaList[i + 1];
        Map<String, dynamic> current = deltaList[i];
        Map<String, dynamic> nextAttr =
            (i == deltaList.length - 1) ? null : next[DeltaKeys.attributes];
        Map<String, dynamic> currentAttr = current[DeltaKeys.attributes];
        Map<String, dynamic> prevAttr =
            (i == 0) ? null : prev[DeltaKeys.attributes];
        if (currentAttr == null ||
            !currentAttr.containsKey(DeltaKeys.a) ||
            !currentAttr.containsKey(DeltaKeys.embed) ||
            currentAttr[DeltaKeys.embed][DeltaKeys.type] != DeltaKeys.image) {
          continue;
        }
        if (nextAttr != null && nextAttr.containsKey(DeltaKeys.a)) {
          current[DeltaKeys.insert] = current[DeltaKeys.insert] + "\n";
        }
        if (prevAttr != null && prevAttr.containsKey(DeltaKeys.a)) {
          current[DeltaKeys.insert] = current[DeltaKeys.insert] + "\n";
          prev[DeltaKeys.insert] = prev[DeltaKeys.insert] + "\n";
        }
      }
    }

    removeRedundantNewLine(deltaFormatList);
    avoidConcatinatingPlainTextAndLineAttributes(deltaFormatList);
    removeZeroWidthSpaceFromNonEmbed(deltaFormatList);
    insertNewlineAfterConsecutiveAnchorTagWithImage(deltaFormatList);
    ensureEndWithNewLine(deltaFormatList);

    Delta delta = Delta.fromJson(deltaFormatList);
    return delta;
  }
}
