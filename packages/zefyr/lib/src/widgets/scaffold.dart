import 'package:flutter/material.dart';

import 'editor.dart';

/// Provides necessary layout for [ZefyrEditor].
class ZefyrScaffold extends StatefulWidget {
  final Widget child;
  final bool showToolbar;

  const ZefyrScaffold({
    Key key,
    this.child,
    this.showToolbar = true,
  }) : super(key: key);

  static ZefyrScaffoldState of(BuildContext context) {
    final widget =
        context.dependOnInheritedWidgetOfExactType<_ZefyrScaffoldAccess>();
    return widget.scaffold;
  }

  @override
  ZefyrScaffoldState createState() => ZefyrScaffoldState();
}

class ZefyrScaffoldState extends State<ZefyrScaffold> {
  WidgetBuilder _toolbarBuilder;

  void showToolbar(WidgetBuilder builder) {
    setState(() {
      _toolbarBuilder = builder;
    });
  }

  void hideToolbar(WidgetBuilder builder) {
    if (_toolbarBuilder == builder) {
      setState(() {
        _toolbarBuilder = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final toolbar =
        (_toolbarBuilder == null) ? Container() : _toolbarBuilder(context);

    var child = widget.child;
    if (widget.showToolbar) {
      child = Column(
        children: [Expanded(child: child), toolbar],
      );
    }
    return _ZefyrScaffoldAccess(scaffold: this, child: child);
  }
}

class _ZefyrScaffoldAccess extends InheritedWidget {
  final ZefyrScaffoldState scaffold;

  _ZefyrScaffoldAccess({Widget child, this.scaffold}) : super(child: child);

  @override
  bool updateShouldNotify(_ZefyrScaffoldAccess oldWidget) {
    return oldWidget.scaffold != scaffold;
  }
}
