import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/create_objective_add_bottom_sheet.dart';

class CreateCard extends StatelessWidget {
  const CreateCard({
    required this.onPressed,
    Key? key,
  }) : super(key: key);

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: .5,
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
            isScrollControlled: true,
            context: context,
            builder: (context) {
              return CreateObjectiveAddBottomSheet(onPressed: onPressed);
            },
          );
        },
        child: Container(
          height: 92,
          child: const Center(
            child: FaIcon(FontAwesomeIcons.plus),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 18,
          ),
          decoration: BoxDecoration(
            color: primaryCard,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
