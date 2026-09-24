import 'package:flutter/material.dart';

class SearchableFontDropdown extends StatefulWidget {
  final String label;
  final String currentFont;
  final ValueChanged<String> onSelected;
  final bool isDark;

  const SearchableFontDropdown({
    Key? key,
    required this.label,
    required this.currentFont,
    required this.onSelected,
    this.isDark = false,
  }) : super(key: key);

  static const List<String> availableFonts = [
    'Jameel Noori Nastaleeq',
    'Amiri',
    'Gulzar',
    'Noto Nastaliq Urdu',
    'Scheherazade New',
    'Roboto',
    'Montserrat',
    'Poppins',
    'Inter',
    'Times New Roman',
    'Arial',
    'Courier New',
    'Amiri Quran',
    'Lateef',
    'Almarai',
  ];

  @override
  State<SearchableFontDropdown> createState() => _SearchableFontDropdownState();
}

class _SearchableFontDropdownState extends State<SearchableFontDropdown> {
  late TextEditingController _controller;
  bool _isExpanded = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentFont);
  }

  @override
  void didUpdateWidget(covariant SearchableFontDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentFont != widget.currentFont && !_isExpanded) {
      _controller.text = widget.currentFont;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final filtered = SearchableFontDropdown.availableFonts.where((f) {
      if (_searchQuery.isEmpty) return true;
      return f.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(
            widget.label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 4),
        ],
        Container(
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.white10 : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isExpanded ? const Color(0xFF0F766E) : Colors.grey.shade300,
              width: _isExpanded ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                style: TextStyle(
                  fontFamily: _controller.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  hintText: '🔍 Search font (e.g. Jameel, Amiri)...',
                  hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 18,
                      color: const Color(0xFF0F766E),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                        if (_isExpanded) _searchQuery = '';
                      });
                    },
                  ),
                ),
                onTap: () {
                  setState(() {
                    _isExpanded = true;
                    _searchQuery = '';
                  });
                },
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _isExpanded = true;
                  });
                },
              ),
              if (_isExpanded)
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No font found matching "$_searchQuery"',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (ctx, idx) {
                            final fontName = filtered[idx];
                            final isSel = fontName == widget.currentFont;
                            final isUrdu = fontName.contains('Jameel') || fontName.contains('Amiri') || fontName.contains('Gulzar') || fontName.contains('Nastaliq');
                            return InkWell(
                              onTap: () {
                                widget.onSelected(fontName);
                                _controller.text = fontName;
                                setState(() {
                                  _isExpanded = false;
                                  _searchQuery = '';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                color: isSel ? const Color(0xFF0F766E).withAlpha(40) : null,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        fontName,
                                        style: TextStyle(
                                          fontFamily: fontName,
                                          fontSize: isUrdu ? 14 : 12,
                                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                          color: isSel ? const Color(0xFF0F766E) : textColor,
                                        ),
                                      ),
                                    ),
                                    if (isUrdu)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F766E).withAlpha(25),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('اردو', style: TextStyle(fontSize: 10, color: Color(0xFF0F766E), fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
