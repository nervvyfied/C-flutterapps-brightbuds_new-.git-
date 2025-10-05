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
        // Visuals
        'assets/cbt/calm/garden_bg.png',
        'assets/cbt/calm/sun.png',
        'assets/cbt/calm/sun_glow.png',
        'assets/cbt/calm/flower_field.png',
        // Audio (multiple segments)
        'assets/audios/calm/01GardenMeditation.m4a',
        'assets/audios/calm/02GardenMeditation.m4a',
        'assets/audios/calm/03GardenMeditation.m4a',
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
        'assets/cbt/sad/sky_bg.png',
        'assets/cbt/sad/cloud.png',
        'assets/cbt/sad/red_band.png',
        'assets/cbt/sad/orange_band.png',
        'assets/cbt/sad/yellow_band.png',
        'assets/cbt/sad/green_band.png',
        'assets/cbt/sad/blue_band.png',
        'assets/cbt/sad/indigo_band.png',
        'assets/cbt/sad/violet_band.png',
        'assets/cbt/sad/sparkle.json',
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
        // Visuals
        'assets/cbt/happy/stretch_up.gif',
        'assets/cbt/happy/wide_hug.gif',
        'assets/cbt/happy/sparkle.json',
        // Audio
        'assets/audios/happy/01HappyStretch.m4a',
        'assets/audios/happy/02HappyStretch.m4a',
        'assets/audios/happy/03HappyStretch.m4a',
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
        'assets/cbt/confused/river_bg.png',
        'assets/cbt/confused/stone1.png',
        'assets/cbt/confused/stone2.png',
        'assets/cbt/confused/stone3.png',
        'assets/cbt/confused/frog.png',
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
        // Visuals
        'assets/cbt/angry/bubble.png',
        'assets/cbt/angry/bubble_pop.png',
        // Audio
        'assets/audios/angry/01BubblePop.m4a',
        'assets/audios/angry/02BubblePop.m4a',
        'assets/audios/angry/03BubblePop.m4a',
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
        'assets/cbt/scared/box_body.png',
        'assets/cbt/scared/box_lid.png',
        'assets/cbt/scared/paper_note.png',
        'assets/cbt/scared/heart_lock.png',
      ],
    ),
  ];

  static CBTExercise getById(String id) =>
      all.firstWhere((e) => e.id == id, orElse: () => all.first);
}
