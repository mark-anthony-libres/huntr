import 'package:flutter/material.dart';

/// What someone is open to on Huntr. Shown as chips on profiles and used as a filter.
enum LookingFor {
  chat('Chat', Icons.chat_bubble_outline),
  friends('Friends', Icons.people_outline),
  dates('Dates', Icons.local_cafe_outlined),
  networking('Networking', Icons.work_outline),
  relationship('Relationship', Icons.favorite_border);

  const LookingFor(this.label, this.icon);
  final String label;
  final IconData icon;
}

class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.age,
    required this.distanceKm,
    required this.bio,
    required this.interests,
    required this.lookingFor,
    required this.online,
    required this.lastActive,
    required this.hue,
    this.pronouns,
    this.heightCm,
    this.verified = false,
  });

  final String id;
  final String name;
  final int age;
  final double distanceKm;
  final String bio;
  final List<String> interests;
  final Set<LookingFor> lookingFor;
  final bool online;
  final DateTime lastActive;

  /// Base hue (0-360) for this person's generated avatar.
  final double hue;
  final String? pronouns;
  final int? heightCm;
  final bool verified;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  String get distanceLabel {
    if (distanceKm < 1) return '${(distanceKm * 1000).round()} m away';
    return '${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)} km away';
  }

  String activeLabel(DateTime now) {
    if (online) return 'Online now';
    final d = now.difference(lastActive);
    if (d.inMinutes < 60) return 'Active ${d.inMinutes}m ago';
    if (d.inHours < 24) return 'Active ${d.inHours}h ago';
    return 'Active ${d.inDays}d ago';
  }
}

enum MessageStatus { sending, sent, read }

class Message {
  Message({
    required this.id,
    required this.fromMe,
    required this.text,
    required this.sentAt,
    this.status = MessageStatus.sent,
  });

  final String id;
  final bool fromMe;
  final String text;
  final DateTime sentAt;
  MessageStatus status;
}

class Conversation {
  Conversation({required this.profile, List<Message>? messages, this.unread = 0})
      : messages = messages ?? [];

  final Profile profile;
  final List<Message> messages;
  int unread;
  bool typing = false;

  Message? get last => messages.isEmpty ? null : messages.last;
}

/// Explore filters. Everything is optional; an empty filter shows everyone.
class ExploreFilters {
  const ExploreFilters({
    this.onlineOnly = false,
    this.maxDistanceKm,
    this.ageRange = const RangeValues(18, 60),
    this.lookingFor = const {},
    this.query = '',
  });

  final bool onlineOnly;
  final double? maxDistanceKm;
  final RangeValues ageRange;
  final Set<LookingFor> lookingFor;
  final String query;

  bool get isDefault =>
      !onlineOnly &&
      maxDistanceKm == null &&
      ageRange.start <= 18 &&
      ageRange.end >= 60 &&
      lookingFor.isEmpty &&
      query.isEmpty;

  ExploreFilters copyWith({
    bool? onlineOnly,
    double? maxDistanceKm,
    bool clearDistance = false,
    RangeValues? ageRange,
    Set<LookingFor>? lookingFor,
    String? query,
  }) {
    return ExploreFilters(
      onlineOnly: onlineOnly ?? this.onlineOnly,
      maxDistanceKm: clearDistance ? null : (maxDistanceKm ?? this.maxDistanceKm),
      ageRange: ageRange ?? this.ageRange,
      lookingFor: lookingFor ?? this.lookingFor,
      query: query ?? this.query,
    );
  }

  bool matches(Profile p) {
    if (onlineOnly && !p.online) return false;
    if (maxDistanceKm != null && p.distanceKm > maxDistanceKm!) return false;
    if (p.age < ageRange.start || p.age > ageRange.end) return false;
    if (lookingFor.isNotEmpty && p.lookingFor.intersection(lookingFor).isEmpty) return false;
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      final hit = p.name.toLowerCase().contains(q) ||
          p.bio.toLowerCase().contains(q) ||
          p.interests.any((i) => i.toLowerCase().contains(q));
      if (!hit) return false;
    }
    return true;
  }
}
