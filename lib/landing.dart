import 'package:flow_builder/flow_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/create_objective_bottom_sheet.dart';
import 'package:rubric/enums.dart';

class Landing extends StatelessWidget {
  final FlowController flowController;

  const Landing({Key key, @required this.flowController}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        foregroundColor: primaryDark,
        backgroundColor: accent,
        child: Icon(Icons.add),
        onPressed: () {
          showModalBottomSheet(
            isScrollControlled: true,
            context: context,
            builder: (context) => CreateObjectiveBottomSheet(),
          );
        },
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: height * .3),
            _logo(),
          ],
        ),
      ),
    );
  }

  Widget _logo() {
    return SvgPicture.asset(
      'assets/images/logo.svg',
      color: primary,
      semanticsLabel: 'rubric logo',
      width: 295,
      height: 89,
    );
  }
}
