import 'package:flutter/material.dart';

class ScrollHook extends StatefulWidget {
  const ScrollHook({
    required this.builder,
    Key? key,
  }) : super(key: key);

  final Widget Function(BuildContext, ScrollController, ScrollHookState)
      builder;

  @override
  ScrollHookState createState() => ScrollHookState();
}

class ScrollHookState extends State<ScrollHook> {
  ScrollController scrollController;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  void scrollToBottom() {
    WidgetsBinding.instance?.addPostFrameCallback((timeStamp) {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.fastOutSlowIn,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, scrollController, this);
  }
}
