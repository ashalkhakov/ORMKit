# Verbalization

`ORMVerbalizer` reads a model out in FORML, worded as Terry Halpin words it
in *Information Modeling and Relational Databases* and *Object-Role
Modeling Fundamentals*, not as NORMA's verbalization browser does. What a
sentence says follows the formal meaning Franconi and Halpin give ORM
(*ORM Abstract Syntax and Semantics*, see ARCHITECTURE.md). Where Halpin's
exact wording could not be checked it is marked **check** below.

## Sentences are statements about something

Each `ORMVerbalSentence` has a `kind` and a `sourceId`, so a sentence can
be put to a domain expert as a question ("does this make sense?") and the
answer turned into a change:

| Kind | What it is | `sourceId` | A "no" means |
| --- | --- | --- | --- |
| Statement | a reading, a constraint, a rule | the constraint (or fact type) | drop or weaken that constraint |
| Possibility | "It is possible that ..." where a constraint is absent | the role (or fact type) a uniqueness constraint would go on | add it |
| Negation | what a statement rules out: its counterexample | the constraint it negates | the constraint is wrong |
| Example | a fact or object of the sample population | the instance | the population or the model is wrong |
| Information | kind, data type, reference mode, notes, fact types played | the element | — |

A statement's `negations` are kept on it, one per way it can fail
(`exactly one` fails by none and by more than one); `verbalizesNegations`
says them too. A deontic rule's negation is "It is forbidden that ...".

## Logic first

Constraints that span fact types and every join path go through
`ORMLogic`: a role sequence is a relation over variables, a join path the
fact atoms it walks. The verbalizer says a formula from a head variable:

- a variable is introduced once with its quantifier ("some Lot", "at most
  one Region", "the same Country") and named again as "that Lot";
- where two or more variables of one type are needed and one is named
  again, they are numbered and named bare: "Person1 is parent of some
  Person2";
- a clause goes on from the object type it ended with as a relative clause
  when a reading starts there ("...is of some LotType that tracks lot
  numbers"; "who" for personal object types), from its subject with
  "and" ("...is part of that Country and has that RegionISOCode"), or else
  as a clause of its own;
- a value restriction names the value ("is of Gender 'M'").

A sequence over several fact types without a join path is joined on the
object type they share, as an external uniqueness constraint is.

## Templates

| Construct | Statement | Negation |
| --- | --- | --- |
| Object type | Person is an entity type. / Reference Scheme: Person has PersonName. / Reference Mode: .Name. / Portable data type: ... | |
| Subtyping | Each Male is a Person. | |
| Subtype derivation | Each Male is by definition a Person who is of Gender 'M'. (partial: Each Person who ... is a Male.) | |
| Objectification | Enrolment is where Student enrolled in Course. | |
| Value constraint | The possible values of Gender are 'M', 'F'. / ... of Age in the context of Person has Age are 0 to 140. | |
| Default value | The default value of Rating is 3. | |
| Object cardinality | Each population of President contains at most one instance. **check** | |
| Role cardinality (unary) | At most one Politician is president. **check** | |
| Uniqueness, binary | Each Person was born in at most one Country. | It is impossible that the same Person was born in more than one Country. |
| Mandatory, binary | Each Person was born in some Country. | It is impossible that some Person was born in no Country. (no reading from the role: ... that for some Person, no Country is the birthplace of that Person.) **check** |
| Both | Each Person was born in exactly one Country. | both of the above |
| No reading from the role | For each Country, at most one Person is president of that Country. | |
| Absent uniqueness | It is possible that some Person speaks more than one Language. | |
| Spanning uniqueness | In each population of Person speaks Language, each Person, Language combination occurs at most once. | It is impossible that the same Person speaks the same Language more than once. |
| Ternary uniqueness | For each Person and Sport, that Person played that Sport for at most one Country. | It is impossible that the same Person played the same Sport for more than one Country. |
| Unary mandatory | Each Person smokes. | |
| External uniqueness | For each Country and RegionISOCode, at most one Region is part of that Country and has that RegionISOCode. | It is impossible that more than one Region is part of the same Country and has the same RegionISOCode. |
| Identification | This association with StreetLine provides the preferred identification scheme for Street. | |
| Inclusive-or | Each Visitor has some Passport or has some DriverLicence. | It is impossible that some Visitor has no Passport and has no DriverLicence. |
| Exclusion, single roles | No Person smokes and drinks. | It is impossible that some Person smokes and drinks. |
| Exclusion, whole binaries | No Person wrote and reviewed the same Book. | It is impossible that the same Person wrote and reviewed the same Book. |
| Exclusion, general | For each A and B, at most one of the following holds: ...; .... | It is impossible that ... and .... |
| Exclusive-or | Each Person is male or is female but not both. / For each A, exactly one of the following holds: ... | |
| Subset | If some Person smokes then that Person is cancer prone. (facts the subset already says of the same variables are not said again) | It is impossible that some Person smokes and it is not true that that Person is cancer prone. **check** |
| Equality | For each Patient, that Patient had some SystolicBP if and only if that Patient had some DiastolicBP. | |
| Frequency | Each Person that has some PhoneNr has at least 2 and at most 5 PhoneNr. / Each A, B combination that occurs in the population of ... occurs there exactly 2 times. **check** | |
| Ring: irreflexive | No Person is parent of itself. **check** ("himself or herself" for personal types?) | It is impossible that some Person is parent of itself. |
| Ring: asymmetric | If Person1 is parent of Person2 then it is impossible that Person2 is parent of Person1. | It is impossible that Person1 is parent of Person2 and Person2 is parent of Person1. |
| Ring: antisymmetric | If Person1 is parent of Person2 and Person1 is not Person2 then it is impossible that Person2 is parent of Person1. | |
| Ring: symmetric, transitive, intransitive, reflexive, purely reflexive | If ... then ... | |
| Ring: acyclic | No Person may cycle back to itself via one or more traversals through Person is parent of Person. **check** | |
| Value comparison | For each Project, if that Project starts on some Date1 and ends on some Date2 then Date1 is less than or equal to Date2. | It is impossible that some Project starts on some Date1 and ends on some Date2 and Date1 is greater than Date2. |
| Deontic | It is obligatory that each Person ... | It is forbidden that ... |
| Fact type derivation | * For each Session and Seat, that Session has that Seat if and only if that Session is at some Cinema that contains some Row that contains that Seat. (numbered heads: * Person1 is grandparent of Person2 if and only if Person1 is parent of some Person3 who is parent of Person2.) | |
| Derivation marks | `*` derived, `**` derived and stored, `+` semiderived (said with "if"), `++` semiderived and stored **check** | |
| Informal derivation | * the modeller's text | |
| Examples | Examples: 'DROC', 'YV', 'BK'. / Club Name 'Dandenong Ranges Orienteering Club' is name of Club 'DROC'. | |

## To check against the book

The wordings marked **check**, and:

- whether Halpin's subset negation is better said with a negated reading
  ("...and that Person is not cancer prone"), which needs readings ORMKit
  does not have;
- whether numbered variables are named again bare ("Person1") or with
  "that" ("that Person1");
- "Portable data type:" and "Informal Definition:" are NORMA's labels, kept
  for the browser; Halpin has no wording for them.

## Next

A parser over the same templates turns a sentence the modeller types
("Each Person was born in exactly one Country.") into the constraint, as
the Fact Editor already does for fact types; the verbalize-then-parse round
trip is its test.
