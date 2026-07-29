import '../../domain/enums.dart';

/// Starter data. Nothing here is a programme the app imposes — it is a catalog
/// of common movements plus a few optional split templates the user can pick
/// from (or ignore entirely and build a regime by hand).
///
/// Deliberately free of personal cues, form videos and past numbers: those are
/// things the user adds, not things the app ships with.

class StarterExercise {
  const StarterExercise({
    required this.key,
    required this.name,
    required this.muscle,
    required this.equipment,
    required this.loadMode,
  });

  final String key;
  final String name;
  final MuscleGroup muscle;
  final Equipment equipment;
  final LoadMode loadMode;
}

/// One exercise slot in a template session.
class TemplateSlot {
  const TemplateSlot(this.exerciseKey, this.sets, {this.repLow, this.repHigh});

  final String exerciseKey;
  final int sets;
  final int? repLow;
  final int? repHigh;
}

class TemplateSession {
  const TemplateSession(this.name, this.slots);

  final String name;
  final List<TemplateSlot> slots;
}

/// A split the user can start from. Session order defines the cycle: one pass
/// through all of them is one cycle.
class RegimeTemplate {
  const RegimeTemplate({
    required this.key,
    required this.name,
    required this.summary,
    required this.sessions,
  });

  final String key;
  final String name;
  final String summary;
  final List<TemplateSession> sessions;

  bool get isBlank => sessions.isEmpty;
}

const starterExercises = <StarterExercise>[
  // ── Chest ─────────────────────────────────────────────────────────────
  StarterExercise(
    key: 'barbell_bench',
    name: 'Barbell Bench Press',
    muscle: MuscleGroup.chest,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'incline_barbell_bench',
    name: 'Incline Barbell Bench Press',
    muscle: MuscleGroup.chest,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'flat_db_bench',
    name: 'Flat DB Bench Press',
    muscle: MuscleGroup.chest,
    equipment: Equipment.dumbbell,
    loadMode: LoadMode.perSide,
  ),
  StarterExercise(
    key: 'incline_db_press',
    name: 'Incline DB Press',
    muscle: MuscleGroup.chest,
    equipment: Equipment.dumbbell,
    loadMode: LoadMode.perSide,
  ),
  StarterExercise(
    key: 'chest_fly',
    name: 'Chest Fly (Machine)',
    muscle: MuscleGroup.chest,
    equipment: Equipment.machine,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'cable_crossover',
    name: 'Cable Crossover',
    muscle: MuscleGroup.chest,
    equipment: Equipment.cable,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'dips',
    name: 'Dips',
    muscle: MuscleGroup.chest,
    equipment: Equipment.bodyweight,
    loadMode: LoadMode.bodyweightPlus,
  ),
  StarterExercise(
    key: 'pushup',
    name: 'Push-up',
    muscle: MuscleGroup.chest,
    equipment: Equipment.bodyweight,
    loadMode: LoadMode.bodyweightPlus,
  ),

  // ── Back ──────────────────────────────────────────────────────────────
  StarterExercise(
    key: 'pullup',
    name: 'Pull-up',
    muscle: MuscleGroup.back,
    equipment: Equipment.bodyweight,
    loadMode: LoadMode.bodyweightPlus,
  ),
  StarterExercise(
    key: 'chinup',
    name: 'Chin-up',
    muscle: MuscleGroup.back,
    equipment: Equipment.bodyweight,
    loadMode: LoadMode.bodyweightPlus,
  ),
  StarterExercise(
    key: 'lat_pulldown',
    name: 'Lat Pulldown',
    muscle: MuscleGroup.back,
    equipment: Equipment.machine,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'seated_row',
    name: 'Seated Row',
    muscle: MuscleGroup.back,
    equipment: Equipment.machine,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'barbell_row',
    name: 'Barbell Row',
    muscle: MuscleGroup.back,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'db_row',
    name: 'Single-arm DB Row',
    muscle: MuscleGroup.back,
    equipment: Equipment.dumbbell,
    loadMode: LoadMode.perSide,
  ),
  StarterExercise(
    key: 'straight_arm_pulldown',
    name: 'Straight-arm Pulldown',
    muscle: MuscleGroup.back,
    equipment: Equipment.cable,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'shrug',
    name: 'Shrug',
    muscle: MuscleGroup.back,
    equipment: Equipment.dumbbell,
    loadMode: LoadMode.perSide,
  ),

  // ── Shoulders ─────────────────────────────────────────────────────────
  StarterExercise(
    key: 'overhead_press',
    name: 'Overhead Press (Barbell)',
    muscle: MuscleGroup.shoulders,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'seated_ohp_db',
    name: 'Seated DB Overhead Press',
    muscle: MuscleGroup.shoulders,
    equipment: Equipment.dumbbell,
    loadMode: LoadMode.perSide,
  ),
  StarterExercise(
    key: 'lateral_raise_db',
    name: 'Lateral Raise (DB)',
    muscle: MuscleGroup.shoulders,
    equipment: Equipment.dumbbell,
    loadMode: LoadMode.perSide,
  ),
  StarterExercise(
    key: 'lateral_raise_machine',
    name: 'Lateral Raise (Machine)',
    muscle: MuscleGroup.shoulders,
    equipment: Equipment.machine,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'reverse_pec_deck',
    name: 'Reverse Pec Deck',
    muscle: MuscleGroup.shoulders,
    equipment: Equipment.machine,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'face_pull',
    name: 'Face Pull',
    muscle: MuscleGroup.shoulders,
    equipment: Equipment.cable,
    loadMode: LoadMode.total,
  ),

  // ── Arms ──────────────────────────────────────────────────────────────
  StarterExercise(
    key: 'barbell_curl',
    name: 'Barbell Curl',
    muscle: MuscleGroup.biceps,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'incline_db_curl',
    name: 'Incline DB Curl',
    muscle: MuscleGroup.biceps,
    equipment: Equipment.dumbbell,
    loadMode: LoadMode.perSide,
  ),
  StarterExercise(
    key: 'preacher_curl',
    name: 'Preacher Curl',
    muscle: MuscleGroup.biceps,
    equipment: Equipment.machine,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'hammer_curl',
    name: 'Hammer Curl',
    muscle: MuscleGroup.biceps,
    equipment: Equipment.dumbbell,
    loadMode: LoadMode.perSide,
  ),
  StarterExercise(
    key: 'triceps_pushdown',
    name: 'Triceps Pushdown',
    muscle: MuscleGroup.triceps,
    equipment: Equipment.cable,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'skullcrusher',
    name: 'Skullcrusher (EZ Bar)',
    muscle: MuscleGroup.triceps,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'overhead_tri_ext',
    name: 'Overhead Triceps Extension',
    muscle: MuscleGroup.triceps,
    equipment: Equipment.dumbbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'reverse_curl',
    name: 'Reverse Curl',
    muscle: MuscleGroup.forearms,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'wrist_curl',
    name: 'Wrist Curl',
    muscle: MuscleGroup.forearms,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),

  // ── Legs ──────────────────────────────────────────────────────────────
  StarterExercise(
    key: 'back_squat',
    name: 'Back Squat',
    muscle: MuscleGroup.quads,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'front_squat',
    name: 'Front Squat',
    muscle: MuscleGroup.quads,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'leg_press',
    name: 'Leg Press',
    muscle: MuscleGroup.quads,
    equipment: Equipment.machine,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'leg_extension',
    name: 'Leg Extension',
    muscle: MuscleGroup.quads,
    equipment: Equipment.machine,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'bulgarian_split_squat',
    name: 'Bulgarian Split Squat',
    muscle: MuscleGroup.quads,
    equipment: Equipment.dumbbell,
    loadMode: LoadMode.perSide,
  ),
  StarterExercise(
    key: 'deadlift',
    name: 'Deadlift',
    muscle: MuscleGroup.hamstrings,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'rdl',
    name: 'Romanian Deadlift',
    muscle: MuscleGroup.hamstrings,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'hamstring_curl',
    name: 'Lying Hamstring Curl',
    muscle: MuscleGroup.hamstrings,
    equipment: Equipment.machine,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'hip_thrust',
    name: 'Hip Thrust',
    muscle: MuscleGroup.glutes,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'standing_calf_raise',
    name: 'Standing Calf Raise',
    muscle: MuscleGroup.calves,
    equipment: Equipment.machine,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'seated_calf_raise',
    name: 'Seated Calf Raise',
    muscle: MuscleGroup.calves,
    equipment: Equipment.machine,
    loadMode: LoadMode.total,
  ),

  // ── Core ──────────────────────────────────────────────────────────────
  StarterExercise(
    key: 'hanging_leg_raise',
    name: 'Hanging Leg Raise',
    muscle: MuscleGroup.core,
    equipment: Equipment.bodyweight,
    loadMode: LoadMode.bodyweight,
  ),
  StarterExercise(
    key: 'toes_to_bar',
    name: 'Toes to Bar',
    muscle: MuscleGroup.core,
    equipment: Equipment.bodyweight,
    loadMode: LoadMode.bodyweight,
  ),
  StarterExercise(
    key: 'cable_crunch',
    name: 'Cable Crunch',
    muscle: MuscleGroup.core,
    equipment: Equipment.cable,
    loadMode: LoadMode.total,
  ),
  StarterExercise(
    key: 'plank',
    name: 'Plank',
    muscle: MuscleGroup.core,
    equipment: Equipment.bodyweight,
    loadMode: LoadMode.bodyweight,
  ),
];

/// Optional starting points. Picking one writes ordinary sessions and slots the
/// user can then rename, reorder, gut or extend — there is nothing special
/// about a regime that came from a template.
const regimeTemplates = <RegimeTemplate>[
  RegimeTemplate(
    key: 'blank',
    name: 'Start from scratch',
    summary: 'An empty regime. Add your own sessions and exercises.',
    sessions: [],
  ),
  RegimeTemplate(
    key: 'ppl6',
    name: 'Push / Pull / Legs · 6 day',
    summary: 'Six sessions per cycle, each movement trained twice with its own '
        'progression.',
    sessions: [
      TemplateSession('Push 1', [
        TemplateSlot('incline_db_press', 3, repLow: 8, repHigh: 12),
        TemplateSlot('flat_db_bench', 3, repLow: 8, repHigh: 10),
        TemplateSlot('chest_fly', 3, repLow: 8, repHigh: 12),
        TemplateSlot('seated_ohp_db', 3, repLow: 6, repHigh: 10),
        TemplateSlot('lateral_raise_machine', 3, repLow: 10, repHigh: 15),
        TemplateSlot('skullcrusher', 3, repLow: 8, repHigh: 12),
      ]),
      TemplateSession('Pull 1', [
        TemplateSlot('pullup', 3, repLow: 5, repHigh: 8),
        TemplateSlot('seated_row', 3, repLow: 8, repHigh: 12),
        TemplateSlot('lat_pulldown', 3, repLow: 8, repHigh: 12),
        TemplateSlot('face_pull', 3, repLow: 12, repHigh: 15),
        TemplateSlot('preacher_curl', 3, repLow: 10, repHigh: 12),
        TemplateSlot('incline_db_curl', 3, repLow: 8, repHigh: 12),
      ]),
      TemplateSession('Leg 1', [
        TemplateSlot('back_squat', 3, repLow: 6, repHigh: 10),
        TemplateSlot('rdl', 3, repLow: 8, repHigh: 10),
        TemplateSlot('leg_press', 3, repLow: 10, repHigh: 12),
        TemplateSlot('hamstring_curl', 3, repLow: 10, repHigh: 12),
        TemplateSlot('standing_calf_raise', 3, repLow: 10, repHigh: 15),
        TemplateSlot('hanging_leg_raise', 3, repLow: 8, repHigh: 12),
      ]),
      // Incline press appears in both push days on purpose: the same movement
      // runs a separate progression in each session, which is the thing this
      // app exists to keep straight.
      TemplateSession('Push 2', [
        TemplateSlot('dips', 3, repLow: 6, repHigh: 10),
        TemplateSlot('incline_db_press', 3, repLow: 8, repHigh: 12),
        TemplateSlot('cable_crossover', 3, repLow: 10, repHigh: 15),
        TemplateSlot('overhead_press', 3, repLow: 6, repHigh: 10),
        TemplateSlot('lateral_raise_db', 3, repLow: 12, repHigh: 20),
        TemplateSlot('triceps_pushdown', 3, repLow: 10, repHigh: 12),
      ]),
      TemplateSession('Pull 2', [
        TemplateSlot('barbell_row', 3, repLow: 6, repHigh: 10),
        TemplateSlot('lat_pulldown', 3, repLow: 8, repHigh: 12),
        TemplateSlot('db_row', 3, repLow: 8, repHigh: 12),
        TemplateSlot('reverse_pec_deck', 3, repLow: 12, repHigh: 15),
        TemplateSlot('hammer_curl', 3, repLow: 10, repHigh: 12),
        TemplateSlot('barbell_curl', 3, repLow: 8, repHigh: 12),
      ]),
      TemplateSession('Leg 2', [
        TemplateSlot('deadlift', 3, repLow: 4, repHigh: 6),
        TemplateSlot('front_squat', 3, repLow: 6, repHigh: 10),
        TemplateSlot('bulgarian_split_squat', 3, repLow: 8, repHigh: 12),
        TemplateSlot('leg_extension', 3, repLow: 12, repHigh: 15),
        TemplateSlot('seated_calf_raise', 3, repLow: 12, repHigh: 15),
        TemplateSlot('cable_crunch', 3, repLow: 10, repHigh: 15),
      ]),
    ],
  ),
  RegimeTemplate(
    key: 'ppl3',
    name: 'Push / Pull / Legs · 3 day',
    summary: 'One push, one pull, one leg day per cycle.',
    sessions: [
      TemplateSession('Push', [
        TemplateSlot('barbell_bench', 3, repLow: 5, repHigh: 8),
        TemplateSlot('incline_db_press', 3, repLow: 8, repHigh: 12),
        TemplateSlot('seated_ohp_db', 3, repLow: 8, repHigh: 12),
        TemplateSlot('lateral_raise_db', 3, repLow: 12, repHigh: 20),
        TemplateSlot('triceps_pushdown', 3, repLow: 10, repHigh: 15),
      ]),
      TemplateSession('Pull', [
        TemplateSlot('pullup', 3, repLow: 5, repHigh: 8),
        TemplateSlot('barbell_row', 3, repLow: 6, repHigh: 10),
        TemplateSlot('seated_row', 3, repLow: 10, repHigh: 12),
        TemplateSlot('face_pull', 3, repLow: 12, repHigh: 15),
        TemplateSlot('incline_db_curl', 3, repLow: 8, repHigh: 12),
      ]),
      TemplateSession('Legs', [
        TemplateSlot('back_squat', 3, repLow: 5, repHigh: 8),
        TemplateSlot('rdl', 3, repLow: 8, repHigh: 10),
        TemplateSlot('leg_press', 3, repLow: 10, repHigh: 12),
        TemplateSlot('hamstring_curl', 3, repLow: 10, repHigh: 12),
        TemplateSlot('standing_calf_raise', 3, repLow: 10, repHigh: 15),
      ]),
    ],
  ),
  RegimeTemplate(
    key: 'upper_lower',
    name: 'Upper / Lower',
    summary: 'Four sessions per cycle: two upper, two lower.',
    sessions: [
      TemplateSession('Upper 1', [
        TemplateSlot('barbell_bench', 3, repLow: 5, repHigh: 8),
        TemplateSlot('barbell_row', 3, repLow: 6, repHigh: 10),
        TemplateSlot('seated_ohp_db', 3, repLow: 8, repHigh: 12),
        TemplateSlot('lat_pulldown', 3, repLow: 8, repHigh: 12),
        TemplateSlot('triceps_pushdown', 3, repLow: 10, repHigh: 15),
        TemplateSlot('incline_db_curl', 3, repLow: 8, repHigh: 12),
      ]),
      TemplateSession('Lower 1', [
        TemplateSlot('back_squat', 3, repLow: 5, repHigh: 8),
        TemplateSlot('rdl', 3, repLow: 8, repHigh: 10),
        TemplateSlot('leg_press', 3, repLow: 10, repHigh: 12),
        TemplateSlot('standing_calf_raise', 3, repLow: 10, repHigh: 15),
        TemplateSlot('hanging_leg_raise', 3, repLow: 8, repHigh: 12),
      ]),
      TemplateSession('Upper 2', [
        TemplateSlot('incline_db_press', 3, repLow: 8, repHigh: 12),
        TemplateSlot('pullup', 3, repLow: 5, repHigh: 8),
        TemplateSlot('seated_row', 3, repLow: 10, repHigh: 12),
        TemplateSlot('lateral_raise_db', 3, repLow: 12, repHigh: 20),
        TemplateSlot('skullcrusher', 3, repLow: 8, repHigh: 12),
        TemplateSlot('hammer_curl', 3, repLow: 10, repHigh: 12),
      ]),
      TemplateSession('Lower 2', [
        TemplateSlot('deadlift', 3, repLow: 4, repHigh: 6),
        TemplateSlot('front_squat', 3, repLow: 6, repHigh: 10),
        TemplateSlot('hamstring_curl', 3, repLow: 10, repHigh: 12),
        TemplateSlot('leg_extension', 3, repLow: 12, repHigh: 15),
        TemplateSlot('seated_calf_raise', 3, repLow: 12, repHigh: 15),
      ]),
    ],
  ),
  RegimeTemplate(
    key: 'full_body',
    name: 'Full body · 3 day',
    summary: 'Three full-body sessions per cycle.',
    sessions: [
      TemplateSession('Full body A', [
        TemplateSlot('back_squat', 3, repLow: 5, repHigh: 8),
        TemplateSlot('barbell_bench', 3, repLow: 5, repHigh: 8),
        TemplateSlot('barbell_row', 3, repLow: 6, repHigh: 10),
        TemplateSlot('lateral_raise_db', 3, repLow: 12, repHigh: 20),
        TemplateSlot('hanging_leg_raise', 3, repLow: 8, repHigh: 12),
      ]),
      TemplateSession('Full body B', [
        TemplateSlot('deadlift', 3, repLow: 4, repHigh: 6),
        TemplateSlot('overhead_press', 3, repLow: 6, repHigh: 10),
        TemplateSlot('lat_pulldown', 3, repLow: 8, repHigh: 12),
        TemplateSlot('leg_press', 3, repLow: 10, repHigh: 12),
        TemplateSlot('triceps_pushdown', 3, repLow: 10, repHigh: 15),
      ]),
      TemplateSession('Full body C', [
        TemplateSlot('front_squat', 3, repLow: 6, repHigh: 10),
        TemplateSlot('incline_db_press', 3, repLow: 8, repHigh: 12),
        TemplateSlot('seated_row', 3, repLow: 10, repHigh: 12),
        TemplateSlot('hamstring_curl', 3, repLow: 10, repHigh: 12),
        TemplateSlot('incline_db_curl', 3, repLow: 8, repHigh: 12),
      ]),
    ],
  ),
];
