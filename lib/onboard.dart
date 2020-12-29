import 'package:flutter/material.dart';
import 'package:rubric/colors.dart';
import 'package:rubric/headline_one.dart';

class Onboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: primaryDark,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeadlineOne('Let’s create your first rubric.'),
              SizedBox(height: 45),
              Container(
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
