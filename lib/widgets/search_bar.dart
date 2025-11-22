import 'package:flutter/material.dart';

class FileSearchBar extends StatelessWidget {
  final Function(String) onSearch;

  const FileSearchBar({
    super.key,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        decoration: const InputDecoration(
          hintText: '搜索文件...',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        onChanged: onSearch,
      ),
    );
  }
}