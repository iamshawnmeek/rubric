import 'package:collection/collection.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/rubric.dart';

// The template catalogue that ships with the app. Template text is content,
// not UI chrome, so it lives here rather than in the ARB file (the same way
// sample data does). Ids are stable so a template can be deep-linked with
// `Routes.rubric(id)`; using a template duplicates it with fresh ids.

/// A rubric that ships with the app, plus who it is written for.
class BuiltinTemplate {
  const new({required this.grades, required this.rubric});

  /// The grade band the wording targets ("Grades 6–12").
  final String grades;
  final Rubric rubric;

  String get id => rubric.id;
}

/// Every built-in template, in catalogue order.
final List<BuiltinTemplate> builtinTemplates = List.unmodifiable(_catalogue);

/// The built-in template with [id], or null.
BuiltinTemplate? builtinTemplateById(String id) =>
    builtinTemplates.firstWhereOrNull((t) => t.id == id);

// ---- Catalogue DSL -------------------------------------------------------

final _shippedAt = DateTime(2026);

const _fourLevels = ['Exemplary', 'Proficient', 'Developing', 'Beginning'];

/// A group of objectives worth [weight] percent.
class _G {
  const new(this.title, this.weight, this.objectives);

  final String title;
  final int weight;
  final List<_O> objectives;
}

/// An objective. For detailed templates, [levels] lists what performance
/// looks like at each level, best first, one entry per level.
class _O {
  const new(this.title, {this.description = '', this.levels = const []});

  final String title;
  final String description;
  final List<String> levels;
}

BuiltinTemplate _template(
  String slug, {
  required String title,
  required String subject,
  required String grades,
  required String description,
  required List<_G> groups,
  GradingMode mode = GradingMode.simple,
  List<String> levels = _fourLevels,
  GradingScale scale = GradingScale.standard,
}) {
  final ladder = [
    for (var i = 0; i < levels.length; i++)
      PerformanceLevel(
        id: '$slug-l${i + 1}',
        label: levels[i],
        points: (levels.length - i).toDouble(),
      ),
  ];
  return BuiltinTemplate(
    grades: grades,
    rubric: Rubric(
      id: 'builtin-$slug',
      title: title,
      subject: subject,
      description: description,
      mode: mode,
      levels: ladder,
      scale: scale,
      isTemplate: true,
      createdAt: _shippedAt,
      updatedAt: _shippedAt,
      groups: [
        for (final (gi, g) in groups.indexed)
          RubricGroup(
            id: '$slug-g${gi + 1}',
            title: g.title,
            weight: g.weight,
            objectives: [
              for (final (oi, o) in g.objectives.indexed)
                Objective(
                  id: '$slug-g${gi + 1}-o${oi + 1}',
                  title: o.title,
                  description: o.description,
                  descriptors: {
                    for (final (li, text) in o.levels.indexed)
                      if (li < ladder.length) ladder[li].id: text,
                  },
                ),
            ],
          ),
      ],
    ),
  );
}

// ---- The catalogue -------------------------------------------------------

final _catalogue = <BuiltinTemplate>[
  _template(
    'persuasive-essay',
    title: 'Persuasive Essay',
    subject: 'English Language Arts',
    grades: 'Grades 6–12',
    description: 'A claim-driven essay that argues a position with evidence and addresses the other side.',
    mode: GradingMode.detailed,
    groups: const [
      _G('Argument', 40, [
        _O(
          'Claim',
          description: 'States a clear, arguable position.',
          levels: [
            'States a precise, arguable claim that frames the whole essay.',
            'States a clear claim that the essay supports.',
            'States a claim, but it is vague or only partly arguable.',
            'The position is missing or cannot be identified.',
          ],
        ),
        _O(
          'Evidence and reasoning',
          description: 'Supports the claim with relevant, explained evidence.',
          levels: [
            'Integrates strong, relevant evidence and explains how each piece proves the claim.',
            'Uses relevant evidence and mostly explains its connection to the claim.',
            'Evidence is thin or loosely connected; explanation is limited.',
            'Little or no evidence; relies on opinion alone.',
          ],
        ),
        _O(
          'Counterclaim',
          description: 'Acknowledges and answers an opposing view.',
          levels: [
            'Fairly presents a strong counterclaim and rebuts it convincingly.',
            'Presents a counterclaim and offers a reasonable rebuttal.',
            'Mentions another view but does not answer it.',
            'Ignores opposing views.',
          ],
        ),
      ]),
      _G('Organization', 30, [
        _O(
          'Structure',
          description: 'Introduction, logically ordered body, conclusion.',
          levels: [
            'Every paragraph builds on the last; the conclusion extends the argument.',
            'Clear introduction, body and conclusion in a logical order.',
            'Structure is present but some paragraphs feel out of place.',
            'No clear structure; ideas are hard to follow.',
          ],
        ),
        _O(
          'Transitions',
          description: 'Connects ideas within and between paragraphs.',
          levels: [
            'Varied, purposeful transitions show how ideas relate.',
            'Transitions connect most ideas smoothly.',
            'Transitions are repetitive or sometimes missing.',
            'Few or no transitions; ideas feel disconnected.',
          ],
        ),
      ]),
      _G('Conventions', 30, [
        _O(
          'Grammar, usage and mechanics',
          levels: [
            'Virtually error-free; sentence variety strengthens the argument.',
            'Minor errors that do not distract from meaning.',
            'Frequent errors that sometimes obscure meaning.',
            'Errors make the essay difficult to read.',
          ],
        ),
        _O(
          'Tone and word choice',
          levels: [
            'Consistently formal, precise and persuasive language.',
            'Mostly formal and appropriate to the audience.',
            'Tone slips into casual language or vague wording.',
            'Tone is inappropriate for an argument.',
          ],
        ),
      ]),
    ],
  ),
  _template(
    'lab-report',
    title: 'Lab Report',
    subject: 'Science',
    grades: 'Grades 9–12',
    description: 'A formal write-up of a controlled experiment, from hypothesis through data analysis to an evidence-based conclusion.',
    mode: GradingMode.detailed,
    groups: const [
      _G('Design and procedure', 25, [
        _O(
          'Question and hypothesis',
          description: 'Poses a testable question and a reasoned hypothesis.',
          levels: [
            'States a testable question and a falsifiable hypothesis justified by scientific reasoning.',
            'States a testable question and a clear hypothesis with a brief rationale.',
            'The question or hypothesis is vague or not testable as written.',
            'The question or hypothesis is missing or unrelated to the investigation.',
          ],
        ),
        _O(
          'Variables and controls',
          description:
              'Identifies the variables and controls that make the test fair.',
          levels: [
            'Identifies independent, dependent and controlled variables and explains how each is managed.',
            'Correctly identifies independent, dependent and controlled variables.',
            'Identifies some variables; controls are incomplete or mislabeled.',
            'Variables and controls are not identified.',
          ],
        ),
        _O(
          'Procedure',
          description:
              'Written so another student could repeat the experiment.',
          levels: [
            'Numbered, precise steps with quantities and safety notes make the experiment easy to replicate.',
            'Steps are clear and complete enough to replicate with minor questions.',
            'Steps lack detail, so replicating the experiment requires guessing.',
            'The procedure is missing or cannot be followed.',
          ],
        ),
      ]),
      _G('Data and results', 25, [
        _O(
          'Data collection',
          description:
              'Records accurate data with units across repeated trials.',
          levels: [
            'Records complete data with units, appropriate precision and repeated trials.',
            'Records complete data with units and enough trials.',
            'Data is incomplete, lacks units or comes from too few trials.',
            'Data is missing or unusable.',
          ],
        ),
        _O(
          'Tables and graphs',
          description: 'Organizes data so trends are easy to see.',
          levels: [
            'Titled, labeled tables and graphs of the right type make trends obvious.',
            'Tables and graphs are labeled with units and suit the data.',
            'Tables or graphs are missing labels or units, or use an unsuitable type.',
            'Data is not organized into tables or graphs.',
          ],
        ),
      ]),
      _G('Analysis and conclusions', 35, [
        _O(
          'Interpretation of data',
          description:
              'Describes patterns and uses calculations to explain results.',
          levels: [
            'Describes trends using specific values and correct calculations, and explains any anomalies.',
            'Describes the main trend with supporting values and correct calculations.',
            'Describes results in general terms; calculations are missing or contain errors.',
            'Restates the data without interpreting it.',
          ],
        ),
        _O(
          'Conclusion',
          description: 'Answers the question and evaluates the hypothesis with evidence.',
          levels: [
            'Accepts or rejects the hypothesis using specific data and connects the results to scientific concepts.',
            'Accepts or rejects the hypothesis and cites data as support.',
            'States a conclusion, but support from the data is weak or missing.',
            'The conclusion is missing or contradicts the data.',
          ],
        ),
        _O(
          'Sources of error',
          description: 'Evaluates sources of error and proposes improvements.',
          levels: [
            'Explains specific sources of error, how each affected the results and a targeted improvement.',
            'Identifies specific sources of error and suggests reasonable improvements.',
            'Lists generic errors such as "human error" without explaining their effect.',
            'Sources of error are not discussed.',
          ],
        ),
      ]),
      _G('Communication', 15, [
        _O(
          'Scientific writing',
          levels: [
            'Concise, objective writing uses scientific vocabulary correctly throughout.',
            'Clear, objective writing uses scientific vocabulary mostly correctly.',
            'Writing is informal or imprecise in places.',
            'Writing is unclear or unscientific throughout.',
          ],
        ),
        _O(
          'Report format',
          levels: [
            'All required sections are present, in order and correctly formatted.',
            'All required sections are present with minor formatting slips.',
            'One or two required sections are missing or out of order.',
            'Several required sections are missing.',
          ],
        ),
      ]),
    ],
  ),
  _template(
    'oral-presentation',
    title: 'Oral Presentation',
    subject: 'Speaking & Listening',
    grades: 'Grades 6–12',
    description: 'A prepared talk that informs or persuades an audience, optionally supported by slides or other visuals.',
    mode: GradingMode.detailed,
    groups: const [
      _G('Content', 40, [
        _O(
          'Knowledge of topic',
          description: 'Shows accurate, thorough understanding of the topic.',
          levels: [
            'Explains the topic accurately and in depth, and answers questions with confidence.',
            'Explains the topic accurately and answers most questions.',
            'Explains parts of the topic; some information is inaccurate or thin.',
            'Shows little understanding; information is inaccurate or missing.',
          ],
        ),
        _O(
          'Supporting details',
          description: 'Backs up main points with facts, examples and sources.',
          levels: [
            'Every main point is supported by specific, credible facts or examples.',
            'Most main points are supported by relevant facts or examples.',
            'Support is general, or only some points are backed up.',
            'Main points are unsupported.',
          ],
        ),
      ]),
      _G('Organization', 25, [
        _O(
          'Opening and closing',
          description: 'Engages the audience and ends with a clear takeaway.',
          levels: [
            'Opens with an engaging hook and closes by reinforcing the main message.',
            'Has a clear introduction and conclusion.',
            'The introduction or conclusion is weak or abrupt.',
            'There is no recognizable introduction or conclusion.',
          ],
        ),
        _O(
          'Logical sequence',
          description: 'Points follow an order the audience can track.',
          levels: [
            'Ideas follow a clear order, with signposts that guide the audience.',
            'Ideas follow a logical order that is easy to follow.',
            'The order is sometimes confusing and the audience may lose track.',
            'Ideas are presented in no clear order.',
          ],
        ),
      ]),
      _G('Delivery', 25, [
        _O(
          'Voice',
          description: 'Volume, pace and clarity.',
          levels: [
            'Speaks clearly at a steady pace and varies tone to stress key points.',
            'Speaks clearly, loudly enough and at an appropriate pace.',
            'Is sometimes too quiet, too fast or unclear.',
            'Is hard to hear or understand for most of the presentation.',
          ],
        ),
        _O(
          'Eye contact and presence',
          description: 'Engages the audience rather than reading.',
          levels: [
            'Holds eye contact with the whole room and glances at notes only briefly.',
            'Makes regular eye contact and checks notes occasionally.',
            'Reads from notes or slides for much of the presentation.',
            'Reads the entire presentation with little or no eye contact.',
          ],
        ),
        _O(
          'Time management',
          description: 'Stays within the time limit.',
          levels: [
            'Uses the time limit fully and gives each section appropriate time.',
            'Finishes within the time limit.',
            'Runs noticeably short of or over the time limit.',
            'Runs far short of or far over the time limit.',
          ],
        ),
      ]),
      _G('Visual aids', 10, [
        _O(
          'Visual support',
          description: 'Visuals clarify the message and are easy to read.',
          levels: [
            'Visuals are readable, purposeful and reinforce each main point.',
            'Visuals are readable and relate to the content.',
            'Visuals are cluttered, hard to read or only loosely related.',
            'Visuals are missing or distract from the message.',
          ],
        ),
      ]),
    ],
  ),
  _template(
    'group-collaboration',
    title: 'Group Project Collaboration',
    subject: 'Cross-curricular',
    grades: 'Grades 4–12',
    description: 'How each student works with a team on a shared project, graded individually.',
    mode: GradingMode.detailed,
    groups: const [
      _G('Contribution', 35, [
        _O(
          'Share of the work',
          description: "Completes a fair share of the group's tasks.",
          levels: [
            'Completes all assigned tasks and helps teammates finish theirs.',
            'Completes all assigned tasks.',
            'Completes some assigned tasks; others must pick up the rest.',
            'Completes little or none of the assigned work.',
          ],
        ),
        _O(
          'Quality of contributions',
          description: 'Brings useful ideas and accurate work.',
          levels: [
            'Offers ideas and work that noticeably improve the final product.',
            'Offers useful ideas and accurate work.',
            'Ideas or work are sometimes off-task or need to be redone.',
            'Rarely offers ideas; work is off-task or inaccurate.',
          ],
        ),
      ]),
      _G('Teamwork', 35, [
        _O(
          'Listening and respect',
          description: 'Listens to teammates and responds respectfully.',
          levels: [
            "Listens actively, builds on others' ideas and invites quieter members in.",
            'Listens to others and responds respectfully.',
            "Sometimes interrupts or dismisses others' ideas.",
            'Often interrupts, ignores or disrespects teammates.',
          ],
        ),
        _O(
          'Resolving disagreements',
          description: 'Works through conflict constructively.',
          levels: [
            'Helps the group reach agreement by proposing fair compromises.',
            'Discusses disagreements calmly and accepts group decisions.',
            'Resists group decisions or disengages when disagreeing.',
            'Creates or escalates conflict.',
          ],
        ),
      ]),
      _G('Responsibility', 30, [
        _O(
          'Meeting deadlines',
          levels: [
            "Finishes every task on or before the group's deadlines.",
            "Finishes tasks by the group's deadlines.",
            'Misses some deadlines, delaying the group.',
            'Regularly misses deadlines.',
          ],
        ),
        _O(
          'Staying on task',
          description: 'Uses group time productively.',
          levels: [
            'Stays focused all session and helps refocus the group.',
            'Stays focused during group work time.',
            'Needs reminders to stay on task.',
            'Is rarely on task during group work time.',
          ],
        ),
      ]),
    ],
  ),
  _template(
    'research-paper',
    title: 'Research Paper',
    subject: 'English Language Arts',
    grades: 'Grades 9–12',
    description: 'A thesis-driven paper that synthesizes credible sources into an original argument with formal citations.',
    groups: const [
      _G('Thesis and argument', 30, [
        _O(
          'Thesis',
          description: 'Full marks: a specific, arguable thesis in the introduction that the whole paper develops.',
        ),
        _O(
          'Analysis',
          description: 'Full marks: explains how each piece of evidence supports the thesis instead of summarizing sources.',
        ),
      ]),
      _G('Research and sources', 30, [
        _O(
          'Source quality',
          description: 'Full marks: meets the required number of credible, relevant sources, including scholarly or primary sources.',
        ),
        _O(
          'Integration of evidence',
          description:
              'Full marks: introduces quotations and paraphrases smoothly and '
              "balances them with the writer's own analysis.",
        ),
      ]),
      _G('Organization', 20, [
        _O(
          'Structure',
          description: 'Full marks: each paragraph opens with a topic sentence tied to the thesis, and paragraphs follow a logical order.',
        ),
        _O(
          'Transitions',
          description: 'Full marks: transitions show how each section connects to the one before it.',
        ),
      ]),
      _G('Citations and conventions', 20, [
        _O(
          'Citations',
          description: 'Full marks: every borrowed idea is cited in-text and matches a correctly formatted works cited entry.',
        ),
        _O(
          'Grammar and style',
          description: 'Full marks: formal academic tone with no errors that distract the reader.',
        ),
      ]),
    ],
  ),
  _template(
    'narrative-writing',
    title: 'Narrative Writing',
    subject: 'English Language Arts',
    grades: 'Grades 3–8',
    description: 'A real or imagined story with developed characters, a clear sequence of events and a resolution.',
    mode: GradingMode.detailed,
    groups: const [
      _G('Ideas and development', 35, [
        _O(
          'Characters and setting',
          description:
              'Introduces who the story is about and where it happens.',
          levels: [
            'Characters and setting are vivid and shown through specific details.',
            'Characters and setting are clearly introduced with some details.',
            'Characters or setting are named but not described.',
            'Characters and setting are unclear or missing.',
          ],
        ),
        _O(
          'Plot and conflict',
          description: 'Builds the story around a problem that gets resolved.',
          levels: [
            'A clear problem builds to a turning point and is resolved in a believable way.',
            'A clear problem is developed and resolved.',
            'A problem is present but is solved too quickly or not at all.',
            'There is no clear problem; events do not add up to a story.',
          ],
        ),
      ]),
      _G('Organization', 25, [
        _O(
          'Beginning, middle and end',
          levels: [
            'Hooks the reader, builds through the middle and ends with a satisfying close.',
            'Has a clear beginning, middle and end.',
            'One part is missing or very brief.',
            'Events are hard to follow, with no clear beginning or end.',
          ],
        ),
        _O(
          'Sequence and transitions',
          description: 'Shows the order of events.',
          levels: [
            'Varied time words and transitions move the reader smoothly through events.',
            'Transitions show the order of events.',
            'Uses the same few transitions, such as "then" and "and then", over and over.',
            'Events jump around with no transitions.',
          ],
        ),
      ]),
      _G('Craft', 25, [
        _O(
          'Dialogue and description',
          description:
              'Uses dialogue, actions and the senses to show, not tell.',
          levels: [
            'Dialogue, actions and sensory details reveal characters and move the story forward.',
            'Uses some dialogue and description to show what happens.',
            'Mostly tells events; dialogue or description is rare.',
            'Only lists events, with no dialogue or description.',
          ],
        ),
        _O(
          'Word choice',
          levels: [
            'Precise verbs and vivid words create clear pictures for the reader.',
            'Uses specific words that fit the story.',
            'Words are often general, such as "good", "nice" or "went".',
            'Word choice is limited or confusing.',
          ],
        ),
      ]),
      _G('Conventions', 15, [
        _O(
          'Spelling, punctuation and grammar',
          levels: [
            'Nearly error-free, including correctly punctuated dialogue.',
            'A few errors that do not get in the way of reading.',
            'Errors sometimes make the story hard to read.',
            'Errors make the story very hard to read.',
          ],
        ),
        _O(
          'Paragraphs',
          levels: [
            'Starts a new paragraph for every new scene and every new speaker.',
            'Starts new paragraphs for most new scenes and speakers.',
            'Uses paragraphs inconsistently.',
            'The story is written as one block of text.',
          ],
        ),
      ]),
    ],
  ),
  _template(
    'math-problem-solving',
    title: 'Math Problem Solving',
    subject: 'Mathematics',
    grades: 'Grades 3–8',
    description: 'A multi-step word problem solved with a chosen strategy, shown work and a written explanation.',
    mode: GradingMode.detailed,
    groups: const [
      _G('Understanding the problem', 20, [
        _O(
          'Identifying what is asked',
          description:
              'Restates the question and finds the information needed.',
          levels: [
            'Restates the question and identifies all needed information, setting aside extra details.',
            'Identifies what the question asks and the information needed.',
            'Identifies part of the question or misses key information.',
            'Misreads the question or cannot say what it asks.',
          ],
        ),
        _O(
          'Representing the problem',
          description: 'Uses a model, diagram, table or equation.',
          levels: [
            'Chooses a model, diagram or equation that shows every relationship in the problem.',
            'Uses a model, diagram or equation that fits the problem.',
            'Uses a model or diagram that is incomplete or partly incorrect.',
            'Has no representation, or one that does not match the problem.',
          ],
        ),
      ]),
      _G('Strategy and reasoning', 30, [
        _O(
          'Choice of strategy',
          levels: [
            'Chooses an efficient strategy and explains why it works.',
            'Chooses a strategy that leads to a solution.',
            'Chooses a strategy that only partly works.',
            'Has no strategy, or one unrelated to the problem.',
          ],
        ),
        _O(
          'Work shown',
          levels: [
            'Shows every step in order, so the reasoning is easy to follow.',
            'Shows the main steps that lead to the answer.',
            'Shows some steps; parts of the reasoning are missing.',
            'Shows only an answer, or no work.',
          ],
        ),
      ]),
      _G('Accuracy', 25, [
        _O(
          'Computation',
          levels: [
            'All calculations are correct.',
            'Calculations are correct except for one minor slip.',
            'Several calculation errors affect the answer.',
            'Calculation errors appear throughout.',
          ],
        ),
        _O(
          'Solution',
          levels: [
            'Gives a correct answer with units and checks that it is reasonable.',
            'Gives a correct answer with units.',
            'The answer is partly correct or missing units.',
            'The answer is incorrect or missing.',
          ],
        ),
      ]),
      _G('Communication', 25, [
        _O(
          'Explaining reasoning',
          levels: [
            'Explains each step clearly and justifies why the answer makes sense.',
            'Explains the steps taken to reach the answer.',
            'The explanation is incomplete or hard to follow.',
            'Gives no explanation of the reasoning.',
          ],
        ),
        _O(
          'Math vocabulary and notation',
          levels: [
            'Uses precise math vocabulary and correct symbols throughout.',
            'Uses math vocabulary and symbols correctly most of the time.',
            'Sometimes uses math vocabulary or symbols incorrectly.',
            'Math vocabulary and symbols are missing or misused.',
          ],
        ),
      ]),
    ],
  ),
  _template(
    'art-project',
    title: 'Art Project',
    subject: 'Visual Arts',
    grades: 'Grades K–12',
    description: 'A studio artwork that applies the elements and principles of art taught in the unit.',
    groups: const [
      _G('Concept and creativity', 30, [
        _O(
          'Original idea',
          description: 'Full marks: the work shows a personal idea that goes beyond copying the example.',
        ),
        _O(
          'Meets the assignment',
          description: 'Full marks: the work includes every requirement given for the project.',
        ),
      ]),
      _G('Elements and principles', 30, [
        _O(
          'Use of art elements',
          description: 'Full marks: purposefully uses the assigned elements, such as line, shape, color, texture or value.',
        ),
        _O(
          'Composition',
          description:
              'Full marks: fills the space with a planned arrangement that '
              "leads the viewer's eye.",
        ),
      ]),
      _G('Craftsmanship', 25, [
        _O(
          'Care with materials',
          description: 'Full marks: materials are used with control, edges are clean and the work is free of smudges or tears.',
        ),
        _O(
          'Completion',
          description: 'Full marks: the work is fully finished, with detail in every area.',
        ),
      ]),
      _G('Reflection', 15, [
        _O(
          'Artist statement',
          description: 'Full marks: explains the idea behind the work and one choice the artist made.',
        ),
        _O(
          'Self-assessment',
          description: 'Full marks: names one strength of the work and one thing to try next time.',
        ),
      ]),
    ],
  ),
  _template(
    'science-fair',
    title: 'Science Fair Project',
    subject: 'Science',
    grades: 'Grades 5–8',
    description: 'An independent investigation presented on a display board and explained to judges.',
    groups: const [
      _G('Scientific method', 35, [
        _O(
          'Testable question',
          description: 'Full marks: asks a question that can be answered by an experiment the student carried out.',
        ),
        _O(
          'Hypothesis',
          description: 'Full marks: makes a prediction with a reason, written as "If…, then…, because…".',
        ),
        _O(
          'Fair test',
          description: 'Full marks: changes only one variable, keeps the others the same and runs at least three trials.',
        ),
      ]),
      _G('Data and conclusions', 35, [
        _O(
          'Data and graphs',
          description: 'Full marks: data is recorded with units in a table and shown in a labeled graph.',
        ),
        _O(
          'Conclusion',
          description: 'Full marks: says whether the hypothesis was supported, using specific results from the data.',
        ),
        _O(
          'Next steps',
          description: 'Full marks: suggests a change or new question based on what was learned.',
        ),
      ]),
      _G('Display', 15, [
        _O(
          'Board layout',
          description: 'Full marks: every section, from question to conclusion, is labeled, in order and readable from a few feet away.',
        ),
        _O(
          'Visuals',
          description: 'Full marks: photos, diagrams or graphs show how the experiment was done.',
        ),
      ]),
      _G('Presentation', 15, [
        _O(
          'Explaining the project',
          description: 'Full marks: explains the project in their own words without reading from the board.',
        ),
        _O(
          'Answering questions',
          description: "Full marks: answers the judges' questions accurately using what was learned.",
        ),
      ]),
    ],
  ),
  _template(
    'reading-response',
    title: 'Reading Response',
    subject: 'English Language Arts',
    grades: 'Grades K–2',
    description: 'A drawing and short writing piece that shows what a young reader understood about a story.',
    mode: GradingMode.detailed,
    levels: const ['Got it', 'Getting there', 'Not yet'],
    groups: const [
      _G('Understanding the story', 50, [
        _O(
          'Characters',
          description: 'I can tell who the story is about.',
          levels: [
            'I can tell who the story is about and how they feel.',
            'I can name who the story is about.',
            'I am not sure who the story is about yet.',
          ],
        ),
        _O(
          'Setting',
          description: 'I can tell where and when the story happens.',
          levels: [
            'I can tell where and when the story happens.',
            'I can tell where or when the story happens.',
            'I am not sure where the story happens yet.',
          ],
        ),
        _O(
          'Retelling',
          description: 'I can retell the beginning, middle and end.',
          levels: [
            'I can retell the beginning, middle and end in order.',
            'I can retell some parts of the story.',
            'I can tell one thing that happened.',
          ],
        ),
      ]),
      _G('Making connections', 25, [
        _O(
          'Connecting to me',
          description: 'I can connect the story to my life.',
          levels: [
            'I can tell how the story is like my life and why.',
            'I can tell how the story is like my life.',
            'I need help to connect the story to my life.',
          ],
        ),
        _O(
          'Favorite part',
          description: 'I can tell my favorite part and why.',
          levels: [
            'I can tell my favorite part and why I like it.',
            'I can tell my favorite part.',
            'I need help to pick a favorite part.',
          ],
        ),
      ]),
      _G('Showing what I know', 25, [
        _O(
          'Drawing',
          description: 'My picture matches the story.',
          levels: [
            'My picture shows the story with lots of details.',
            'My picture shows part of the story.',
            'My picture does not match the story yet.',
          ],
        ),
        _O(
          'Writing',
          description: 'I can write about the story.',
          levels: [
            'I wrote a sentence about the story with a capital and a period.',
            'I wrote some words about the story.',
            'I need help to write about the story.',
          ],
        ),
      ]),
    ],
  ),
  _template(
    'class-participation',
    title: 'Class Participation',
    subject: 'Cross-curricular',
    grades: 'Grades 6–12',
    description: 'How a student engages in discussion and class activities over a grading period.',
    groups: const [
      _G('Engagement', 40, [
        _O(
          'Active listening',
          description: 'Full marks: follows the speaker, takes notes when appropriate and responds to what was actually said.',
        ),
        _O(
          'Contributions',
          description: 'Full marks: offers relevant ideas or questions in every class without being prompted.',
        ),
      ]),
      _G('Discussion skills', 35, [
        _O(
          'Building on others',
          description: 'Full marks: responds to classmates by extending, questioning or respectfully challenging their ideas.',
        ),
        _O(
          'Using evidence',
          description: 'Full marks: supports comments with evidence from the text, notes or course material.',
        ),
      ]),
      _G('Preparation', 25, [
        _O(
          'Readiness',
          description: 'Full marks: arrives on time with materials and has completed the assigned reading or homework.',
        ),
        _O(
          'Time on task',
          description: 'Full marks: uses work time productively and stays focused without reminders.',
        ),
      ]),
    ],
  ),
  _template(
    'coding-project',
    title: 'Coding Project',
    subject: 'Computer Science',
    grades: 'Grades 9–12',
    description: 'A program built to a written specification, submitted with source code, documentation and tests.',
    mode: GradingMode.detailed,
    groups: const [
      _G('Functionality', 35, [
        _O(
          'Meets requirements',
          description: 'The program does what the specification asks.',
          levels: [
            'Every required feature works correctly, including edge cases.',
            'All required features work for typical input.',
            'Some required features are missing or only partly work.',
            'The program does not run, or most features do not work.',
          ],
        ),
        _O(
          'Error handling',
          description: 'Handles invalid input and unexpected states.',
          levels: [
            'Anticipates invalid input and recovers with helpful messages.',
            'Handles common invalid input without crashing.',
            'Crashes or misbehaves on some invalid input.',
            'Crashes on most invalid input.',
          ],
        ),
      ]),
      _G('Code quality', 25, [
        _O(
          'Readability',
          description: 'Names, formatting and layout.',
          levels: [
            'Descriptive names and consistent formatting make the code easy to read at a glance.',
            'Names are meaningful and formatting is mostly consistent.',
            'Some names are unclear or formatting is inconsistent.',
            'Names and formatting make the code hard to read.',
          ],
        ),
        _O(
          'Modularity',
          description: 'Breaks the program into focused functions or classes.',
          levels: [
            'Logic is split into small, focused functions or classes with no repeated code.',
            'Logic is organized into functions or classes with little repetition.',
            'Some functions do too much, or code is repeated.',
            'All logic is in one block with heavy repetition.',
          ],
        ),
      ]),
      _G('Design and problem solving', 25, [
        _O(
          'Algorithm design',
          levels: [
            'Chooses efficient algorithms and data structures and justifies the choice.',
            'Chooses algorithms and data structures that solve the problem correctly.',
            'The approach works but is inefficient or overly complicated.',
            'The approach does not solve the problem.',
          ],
        ),
        _O(
          'Planning',
          description:
              'Plans before coding with pseudocode, diagrams or a spec.',
          levels: [
            'Pseudocode or diagrams map the whole solution and match the final code.',
            'Pseudocode or diagrams cover the main parts of the solution.',
            'Planning is sketchy or does not match the final code.',
            'There is no evidence of planning.',
          ],
        ),
      ]),
      _G('Documentation and testing', 15, [
        _O(
          'Comments and README',
          levels: [
            'Comments explain why, and the README covers setup, usage and known limits.',
            'Comments explain key sections, and the README explains how to run the program.',
            'Comments are sparse or only restate the code.',
            'There are no comments or README.',
          ],
        ),
        _O(
          'Testing',
          levels: [
            'Tests cover normal, boundary and invalid cases, and all pass.',
            'Tests cover the main features and pass.',
            'Tests are few or cover only one case.',
            'There is no evidence of testing.',
          ],
        ),
      ]),
    ],
  ),
  _template(
    'debate',
    title: 'Debate',
    subject: 'Social Studies',
    grades: 'Grades 9–12',
    description: 'A structured team debate on a resolution, with constructive speeches, cross-examination and rebuttals.',
    groups: const [
      _G('Argument and evidence', 40, [
        _O(
          'Constructive case',
          description:
              'Full marks: presents clear contentions that directly support '
              "the team's side of the resolution.",
        ),
        _O(
          'Evidence',
          description: 'Full marks: supports each contention with credible, cited facts, statistics or expert testimony.',
        ),
        _O(
          'Reasoning',
          description: 'Full marks: explains how the evidence proves each contention, with no gaps in logic.',
        ),
      ]),
      _G('Rebuttal', 30, [
        _O(
          'Responding to opponents',
          description: "Full marks: answers the opponents' strongest points and exposes flaws in their evidence or logic.",
        ),
        _O(
          'Cross-examination',
          description: 'Full marks: asks focused questions that reveal weaknesses and answers questions directly.',
        ),
      ]),
      _G('Delivery', 20, [
        _O(
          'Speaking',
          description: 'Full marks: speaks clearly and persuasively with steady eye contact and minimal reading.',
        ),
        _O(
          'Time use',
          description:
              'Full marks: uses the allotted time fully without going over.',
        ),
      ]),
      _G('Conduct', 10, [
        _O(
          'Respect and format',
          description: 'Full marks: critiques ideas rather than people and follows the speaking order and format rules.',
        ),
        _O(
          'Teamwork',
          description: 'Full marks: coordinates with teammates so arguments build on each other without repeating.',
        ),
      ]),
    ],
  ),
  _template(
    'portfolio',
    title: 'Portfolio Review',
    subject: 'Visual Arts',
    grades: 'Grades 9–12',
    description: 'A curated body of work with an artist statement, reviewed for quality, growth and presentation.',
    scale: GradingScale.plusMinus,
    groups: const [
      _G('Body of work', 40, [
        _O(
          'Selection',
          description:
              'Full marks: includes the required number of pieces, chosen to '
              "show the artist's strongest work and range.",
        ),
        _O(
          'Technical skill',
          description: 'Full marks: pieces show confident control of the media and techniques used.',
        ),
        _O(
          'Personal voice',
          description: 'Full marks: a consistent theme, style or line of inquiry connects the work.',
        ),
      ]),
      _G('Growth and reflection', 35, [
        _O(
          'Evidence of growth',
          description: 'Full marks: includes sketches, drafts or early work that show how skills developed over time.',
        ),
        _O(
          'Artist statement',
          description: 'Full marks: explains the intent, process and influences behind the body of work.',
        ),
        _O(
          'Self-critique',
          description: 'Full marks: names specific strengths and next steps using art vocabulary.',
        ),
      ]),
      _G('Presentation', 25, [
        _O(
          'Organization',
          description: 'Full marks: pieces are sequenced purposefully and labeled with title, media, size and date.',
        ),
        _O(
          'Documentation quality',
          description: 'Full marks: photos or scans are in focus, evenly lit, cropped and color-accurate.',
        ),
      ]),
    ],
  ),
  _template(
    'video-project',
    title: 'Video Project',
    subject: 'Media Arts',
    grades: 'Grades 6–12',
    description: 'A short planned, filmed and edited video that tells a story or delivers a message.',
    groups: const [
      _G('Storytelling', 35, [
        _O(
          'Message',
          description: 'Full marks: the video communicates a clear message or story that fits the assignment and audience.',
        ),
        _O(
          'Structure',
          description: 'Full marks: has a clear beginning, middle and end, and every scene moves the story forward.',
        ),
      ]),
      _G('Filming', 25, [
        _O(
          'Shot composition',
          description: 'Full marks: uses a variety of steady, well-framed wide, medium and close-up shots chosen for effect.',
        ),
        _O(
          'Lighting',
          description:
              'Full marks: subjects are clearly lit and visible in every shot.',
        ),
      ]),
      _G('Editing and sound', 25, [
        _O(
          'Editing',
          description: 'Full marks: cuts and transitions are smooth, and pacing keeps the viewer engaged.',
        ),
        _O(
          'Audio',
          description: 'Full marks: dialogue is clear, and music and effects support the mood without drowning out speech.',
        ),
        _O(
          'Credits and permissions',
          description: 'Full marks: credits list every contributor, and all music and media are original or properly licensed.',
        ),
      ]),
      _G('Planning', 15, [
        _O(
          'Storyboard or script',
          description: 'Full marks: a complete storyboard or script was finished before filming and guided the final video.',
        ),
        _O(
          'Deadlines',
          description: 'Full marks: each milestone (plan, footage, rough cut, final) was met on time.',
        ),
      ]),
    ],
  ),
  _template(
    'document-analysis',
    title: 'Primary Source Analysis',
    subject: 'Social Studies',
    grades: 'Grades 6–12',
    description: 'A written analysis of a primary source that examines who made it, why, and what it reveals about its time.',
    mode: GradingMode.detailed,
    groups: const [
      _G('Sourcing', 25, [
        _O(
          'Author and audience',
          description: 'Identifies who created the source, when and for whom.',
          levels: [
            'Identifies the author, date and intended audience and explains how each shapes the source.',
            'Identifies the author, date and intended audience.',
            'Identifies some sourcing information; parts are missing or inaccurate.',
            'Does not identify who created the source or when.',
          ],
        ),
        _O(
          'Purpose and point of view',
          levels: [
            "Explains the creator's purpose and point of view with evidence from the source.",
            "Identifies the creator's purpose and point of view.",
            'Identifies purpose or point of view, but not both, or without support.',
            'Does not address purpose or point of view.',
          ],
        ),
      ]),
      _G('Contextualization', 20, [
        _O(
          'Historical context',
          description:
              'Places the source in the events and conditions of its time.',
          levels: [
            'Connects the source to specific events and conditions of its time and explains their influence.',
            'Connects the source to relevant events of its time.',
            'Mentions the time period in general terms only.',
            'Gives no historical context, or inaccurate context.',
          ],
        ),
        _O(
          'Significance',
          description: 'Explains why the source matters to the larger topic.',
          levels: [
            'Explains what the source reveals about its period and why that matters to the larger topic.',
            'Explains why the source is significant to the topic.',
            'States that the source is important without explaining why.',
            'Does not address significance.',
          ],
        ),
      ]),
      _G('Close reading', 30, [
        _O(
          'Main idea',
          description: 'Summarizes what the source says or shows.',
          levels: [
            'Accurately summarizes the main idea and key details in own words.',
            'Accurately summarizes the main idea.',
            'The summary is partly accurate or copies the source.',
            'The summary is missing or inaccurate.',
          ],
        ),
        _O(
          'Textual evidence',
          levels: [
            'Quotes or cites specific details and explains what each reveals.',
            'Quotes or cites relevant details to support the analysis.',
            'Uses few details, or does not explain them.',
            'Uses no details from the source.',
          ],
        ),
        _O(
          'Inference',
          description:
              'Reads between the lines to find what the source implies.',
          levels: [
            'Draws well-supported inferences about what the source implies but does not state.',
            'Draws reasonable inferences supported by the source.',
            'Inferences are weakly supported or stray from the source.',
            'Makes no inferences beyond restating the source.',
          ],
        ),
      ]),
      _G('Evaluation', 25, [
        _O(
          'Reliability and limits',
          levels: [
            'Evaluates how reliable the source is and what it leaves out, with specific reasons.',
            "Evaluates the source's reliability and names one limitation.",
            'Judges reliability without giving reasons.',
            'Does not evaluate reliability.',
          ],
        ),
        _O(
          'Corroboration',
          levels: [
            'Compares the source with other evidence, explaining where they agree and conflict.',
            'Compares the source with at least one other source.',
            'Mentions another source without comparing the two.',
            'Does not compare the source with other evidence.',
          ],
        ),
      ]),
    ],
  ),
];
