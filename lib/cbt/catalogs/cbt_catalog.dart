import '../models/cbt_exercise_model.dart';

class CBTLibrary {
  static List<CBTExercise> all = [
    // 🌿 Calm Mood
    CBTExercise(
      id: 'calm_garden',
      title: 'Garden Meditation',
      mood: 'calm',
      mode: 'Audio + Visual',
      recurrence: 'daily',
      description:
          'A guided 1-minute meditation to help children relax, breathe, and feel safe while imagining a peaceful garden.',
      duration: '1 minute',
      assets: [
        'garden_bg.png',
        'sun.png',
        'sun_glow.png',
        'flower_field.png',
      ],
    ),

    // 🌈 Sad Mood
    CBTExercise(
      id: 'sad_rainbow',
      title: 'Gratitude Rainbow',
      mood: 'sad',
      mode: 'Visual + Interactive',
      recurrence: 'weekly',
      description:
          'Tap each rainbow color to express gratitude and build your own “Gratitude Rainbow.”',
      duration: '30s - 1 minute',
      assets: [
        'sky_bg.png',
        'cloud.png',
        'red_band.png',
        'orange_band.png',
        'yellow_band.png',
        'green_band.png',
        'blue_band.png',
        'indigo_band.png',
        'violet_band.png',
        'sparkle.json',
      ],
    ),

    // ☀️ Happy Mood
    CBTExercise(
      id: 'happy_stretch',
      title: 'Happy Stretch',
      mood: 'happy',
      mode: 'Visual + Audio',
      recurrence: 'daily',
      description:
          'A fun 1-minute stretching routine with voice prompts and a cheerful sun animation to boost happiness.',
      duration: '1 minute',
      assets: [
        'Stretch_up.gif',
        'wide_hug.gif',
        'sparkle.json',
      ],
    ),

    // ❓ Confused/Uncertain Mood
    CBTExercise(
      id: 'confused_stepstone',
      title: 'Step Stone',
      mood: 'confused',
      mode: 'Visual + Interactive',
      recurrence: 'weekly',
      description:
          'Helps children process confusion by expressing what confuses them, what they understand, and what they can try next.',
      duration: '30s - 1 minute',
      assets: [
        'river_bg.png',
        'stone1.png',
        'stone2.png',
        'stone3.png',
        'frog.png',
      ],
    ),

    // 🔥 Angry Mood
    CBTExercise(
      id: 'angry_bubble',
      title: 'Bubble Pop Exercise',
      mood: 'angry',
      mode: 'Visual + Audio',
      recurrence: 'weekly',
      description:
          'A calming breathing exercise where a red bubble expands and pops as anger is released and calm returns.',
      duration: '1 - 2 minutes',
      assets: [
        'bubble.png',
        'bubble_pop.png',
      ],
    ),

    // 💭 Scared/Worried Mood
    CBTExercise(
      id: 'scared_worrybox',
      title: 'Worry Box',
      mood: 'scared',
      mode: 'Visual + Text',
      recurrence: 'weekly',
      description:
          'Encourages children to write down and “lock away” their worries, teaching emotional safety and release.',
      duration: '1 - 2 minutes',
      assets: [
        'box_body.png',
        'box_lid.png',
        'paper_note.png',
        'heart_lock.png',
      ],
    ),
  ];

  static CBTExercise getById(String id) =>
      all.firstWhere((e) => e.id == id, orElse: () => all.first);
}
