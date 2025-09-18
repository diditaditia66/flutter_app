import 'package:flutter/material.dart';

class InputField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool isNumeric;

  const InputField({
    super.key,
    required this.label,
    required this.controller,
    this.onTap,
    this.isNumeric = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextField(
          controller: controller,
          readOnly: onTap != null,
          keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration.collapsed(hintText: label),
        ),
      ),
    );
  }
}
