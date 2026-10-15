import 'dart:math';

import '../models/models.dart';

/// Sample people for the prototype. Generated from a fixed seed so the grid looks the same on every run.
List<Profile> buildSampleProfiles({DateTime? now}) {
  final clock = now ?? DateTime.now();
  final rnd = Random(7);
  const names = [
    'Alex', 'Jordan', 'Sam', 'Riley', 'Casey', 'Morgan', 'Jamie', 'Taylor', 'Avery', 'Quinn',
    'Rowan', 'Elliot', 'Kai', 'Noah', 'Leo', 'Mateo', 'Ezra', 'Miguel', 'Paolo', 'Rafael',
    'Gabe', 'Luis', 'Nico', 'Andre', 'Marco', 'Theo', 'Julian', 'Adrian', 'Liam', 'Ethan',
    'Ken', 'Joaquin', 'Carlo', 'Dante', 'Isaac', 'Felix',
  ];
  const interests = [
    'Coffee', 'Hiking', 'Gym', 'Gaming', 'Anime', 'Music', 'Travel', 'Photography', 'Cooking',
    'Movies', 'Books', 'Basketball', 'Running', 'Art', 'Design', 'Coding', 'Beach', 'Karaoke',
    'Dogs', 'Cats', 'Food trips', 'Dancing', 'Volleyball', 'Yoga',
  ];
  const bios = [
    'New in town and looking for good coffee spots. Show me around?',
    'Weekend hiker, weekday desk warrior. Always down for food trips.',
    'Designer by day, karaoke legend by night. Say hi!',
    'Into gym, anime and long walks to the convenience store.',
    'Here to meet new friends and see where it goes.',
    'Dog dad. Ask me about my dog, I will send pictures.',
    'Just moved here for work. Let\'s grab a drink sometime.',
    'Music, movies and making people laugh. Not great at bios.',
    'Coffee first, conversations later.',
    'Looking for real conversations, not just "hey".',
    'Traveler. Next stop: wherever the cheapest flight goes.',
    'Developer who cooks too much. Will feed you.',
  ];
  const pronouns = ['he/him', 'he/they', 'they/them', null, null];
  final looking = LookingFor.values;

  final profiles = <Profile>[];
  for (var i = 0; i < names.length; i++) {
    final picks = (List.of(interests)..shuffle(rnd)).take(3 + rnd.nextInt(3)).toList();
    final wants = <LookingFor>{
      looking[rnd.nextInt(looking.length)],
      if (rnd.nextBool()) looking[rnd.nextInt(looking.length)],
    };
    final online = rnd.nextDouble() < 0.45;
    profiles.add(Profile(
      id: 'p$i',
      name: names[i],
      age: 19 + rnd.nextInt(24),
      distanceKm: double.parse((0.2 + pow(rnd.nextDouble(), 2) * 24).toStringAsFixed(1)),
      bio: bios[rnd.nextInt(bios.length)],
      interests: picks,
      lookingFor: wants,
      online: online,
      lastActive: online ? clock : clock.subtract(Duration(minutes: 5 + rnd.nextInt(60 * 48))),
      hue: rnd.nextDouble() * 360,
      pronouns: pronouns[rnd.nextInt(pronouns.length)],
      heightCm: 160 + rnd.nextInt(30),
      verified: rnd.nextDouble() < 0.35,
    ));
  }
  profiles.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  return profiles;
}

/// Friendly canned replies used to simulate the other person while there is no backend.
const sampleReplies = [
  'Hey! 👋 How\'s your day going?',
  'Haha nice, tell me more',
  'I\'m around this weekend, you?',
  'That sounds fun! 😄',
  'Coffee sometime?',
  'Just got home from work, finally free',
  'Same here honestly',
  'Where are you from originally?',
];

const quickReplies = [
  'Hey! 👋',
  'How\'s your day?',
  'Coffee sometime? ☕',
  'What are you up to?',
  'Love your bio 😄',
];
