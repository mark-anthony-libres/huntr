import 'package:flutter/services.dart';

/// Typed faces (":)", "<3", ...) and the emoji they become, in chats and
/// Threads comments. Only on their own, as a word: "http://", "a:b" or
/// "(plan B)" stay as they are.
const emoticons = <String, String>{
  ':)': '🙂',
  ':-)': '🙂',
  '=)': '🙂',
  ':D': '😃',
  ':-D': '😃',
  'XD': '😆',
  'xD': '😆',
  ';)': '😉',
  ';-)': '😉',
  ':(': '🙁',
  ':-(': '🙁',
  ":'(": '😢',
  ":')": '🥲',
  ':P': '😛',
  ':p': '😛',
  ':-P': '😛',
  ':-p': '😛',
  ':O': '😮',
  ':o': '😮',
  ':-O': '😮',
  ':*': '😘',
  ':-*': '😘',
  ':/': '😕',
  ':-/': '😕',
  ':|': '😐',
  ':-|': '😐',
  '>:(': '😠',
  '^_^': '😊',
  '^^': '😊',
  '-_-': '😑',
  '<3': '❤️',
  '</3': '💔',
};

/// Every emoticon in [text] that stands on its own, as its emoji (what is
/// sent, so one left at the end is changed too).
String replaceEmoticons(String text) => text.replaceAllMapped(
    _onItsOwn, (m) => emoticons[m[0]] ?? m[0]!);

// longest first: ":-)" before ":)"
final _onItsOwn = RegExp(
    '(?<=^|\\s)(?:${(emoticons.keys.toList()..sort((a, b) => b.length - a.length)).map(RegExp.escape).join('|')})(?=\\s|\$)');

/// As you type: the emoticon just before a space or a new line becomes its
/// emoji (the one being typed is left alone, so ":P" isn't caught at ":").
class EmoticonFormatter extends TextInputFormatter {
  const EmoticonFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final cursor = newValue.selection.baseOffset;
    final text = newValue.text;
    // only when one space or new line was just typed
    if (!newValue.selection.isCollapsed ||
        cursor < 2 ||
        text.length != oldValue.text.length + 1 ||
        !RegExp(r'\s').hasMatch(text[cursor - 1])) {
      return newValue;
    }
    final before = text.substring(0, cursor - 1);
    final start = before.lastIndexOf(RegExp(r'\s')) + 1;
    final emoji = emoticons[before.substring(start)];
    if (emoji == null) return newValue;
    final changed =
        text.substring(0, start) + emoji + text.substring(cursor - 1);
    return TextEditingValue(
      text: changed,
      selection: TextSelection.collapsed(
          offset: start + emoji.length + 1),
    );
  }
}
