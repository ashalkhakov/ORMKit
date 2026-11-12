# Forms and flows

Two words added to ORM's vocabulary:

- **A form** is the part of the model a user fills in or reads: some facts
  about one object, what must hold of them, and where they come from and
  go to. It is written in the model, in the model's terms, as a
  conceptual query is ([QUERIES.md](QUERIES.md)), and generated: an XForms
  document, and a table an app runs it with.
- **A flow** is an actor's way through forms and lists: which screen leads
  to which, on what action, giving what. It lives in a `.flow` file beside
  the model, and can be played over the model's sample population before
  any app exists.

How either looks, and how it is laid out, is not the model's business. Any
XForms processor runs a generated form, a native view can be laid over it,
and its developers can customize it without losing what they did when it
is generated again.

## How it relates to ORM

The vocabulary follows Halpin and Weber, "Form-and-Fact Based Modeling"
(EMMSAD 2012, LNBIP 113, pp. 285–299), which joins fact-based modelling
(ORM, its verbalizations, the CSDP) with Weber's form-oriented analysis.
We have read its abstract and summaries, not the full text:

| The paper | Here |
| --- | --- |
| a conceptual form is an ORM subschema: the fact types it is about, with their constraints, without its layout | a form is a query of kind Form; read as its subschema (`-[ORMQuery subschemaInModel:]`): the fact types its steps go through, the object types they reach, the constraints whose roles are all among them |
| a form filled in is a population of that subschema | the form's instance is that population for one object, named as the mapping names its properties; saving it adds those facts to the store |
| fact types are anchored to a major object type | a form's outline is anchored at an object type: the object made or changed |
| the model generates the user interface, then it is customized | the XForms document and its table are generated; a customized copy, or a view of the app's own, is checked against the form as a contract |
| constraints are enforced in the form | each constraint whose roles are all in the form is a bind, its alert the constraint's verbalization |
| constraints a form does not show are met as errors, in words | the rest are checked where the form is saved, and the refusal says the rule's verbalization at the element it is about |
| prototype forms seed the model (the CSDP's first step) | planned: a form, or a sample filled in, proposes fact types |
| screen transition diagrams: pages, changed on an atomic action | flows: screens, transitions on a submission, a choice, a cancel, a trigger |

So nothing in a form is new to the model: every element is a role of a
fact type the model has, every check a constraint or rule it has, every
label a role's name or reading. What a form adds is a selection (which
facts, about which object) and a part for each (entered, shown, given).
What is ours beyond the paper: the form as a kind of conceptual query, its
mapping to XForms, the binds from the constraints, the store and OData
requests in and out, flows, and the bridge to BPMN.

A flow is about screens, which the model is not, so it is not in the
model: it refers to the model's forms and lists by id, and what a
transition gives the next form is facts of the one before (the vehicle
chosen).

Why XForms: it is the standard for exactly this split. A form's model
(instances, binds: type, required, relevant, readonly, constraint,
calculate), its intent-level controls (input, select1, output, repeat,
group), and its submissions, with nothing about layout. XFormsKit
(`../XFormsKit`) runs XForms 1.1 natively on macOS, iOS and GNUstep, and
passes the W3C suite; a browser runs the same document with XSLTForms.

## The form vocabulary

A form is an outline, as a query is, anchored at an object type and
starting `Form <Name>:`. Each line is a step from the line above it, by a
fact type's reading, to an object type. What a node is to the form is
marked:

| Mark | The node | Example |
| --- | --- | --- |
| `X (entered)` | entered: the user gives its value; the form asserts the fact | `+ took Litres (entered)` |
| `X (shown)` | shown: read, not changed | `+ has Plate (shown)` |
| `X = ?` | given: its value comes in as the form opens, a parameter; may be entered or shown too (`City = ? (entered)`) | `+ is of Vehicle = ?` |
| none | the way to something entered or shown, or a condition | `+ is at Address` |
| `+ <reading> (entered)` | a unary fact entered (a flag) | `+ filled the tank (entered)` |
| `X = <expr> (shown)` | a value node: computed from the form's values and shown ([EXPRESSIONS.md](EXPRESSIONS.md)) | `PricePerUnit = Money / Volume (shown)` |

The anchor is given when the form changes an object that exists, and new
when it makes one. Where a node sits in the outline says the rest; [The
definition](#the-definition-what-each-node-of-a-form-is) below says it
exactly, and which outlines are no form at all.

Fleet's forms ([Samples/Fleet.orm](../Samples/Fleet.orm)) show each:

```
Form RecordFillUp:
FillUp
  + is of Vehicle1 = ?
    + has Plate (shown)
  + was at Moment (entered)
  + took Litres (entered)
  + was of Fuel (entered)
  + was at Station (entered)
  + cost Money (entered)
  + had driver Driver (entered)
    + drives Vehicle1
  + filled the tank (entered)

Form NewStation:
Station
  + is called StationName (entered)
  + is at Address
    + has AddressLines (entered)
    + is in City (entered)

Form NewRecord:
Record
  + is of Vehicle = ?
  + is FillUp
    + was at Moment (entered)
    + took Litres (entered)
    + was of Fuel (entered)
    + was at Station (entered)
    + cost Money (entered)
    + had driver Driver (entered)
    + filled the tank (entered)
  + is Service
    + was on Day (entered)
```

**Several anchors.** A form may be made or changed with others, objects
neither reaches through the other (a customer and a supplier onboarded
together), its header naming them: `Form Onboard, with NewSupplier:`
(`With` in the `.orm`, the forms' ids; each of one anchor). Each is a form
of its own, opened with the same inputs; its document has them all, an
element of the instance each, named as its form, read each by its key
(`form:read/<Form>`), saved as one: the store once, the service one
change set (`$batch`); refused, none is, each other one's refusals said
under its name (`NewSupplier/contact/contactName`).

A form is verbalized as a query is. In the `.orm` it is a query with
`Kind="Form"`, a node's part `Part="Entered"` or `"Shown"`, a given one
`Given="true"`, a unary's part on its step. **Save a Copy for NORMA**
leaves them out.

## The definition: what each node of a form is

A form's outline is a conceptual query (ConQuer's paths through the
model's fact types, [QUERIES.md](QUERIES.md)) with each node given one
meaning. Following form-oriented analysis, a form is two typed things: what
it **submits**, "an editable method call" whose "actual parameter list is
given by the contents of the input elements", and what it **shows**, a
report; "server action types describe input capabilities, while client
page types are high-level descriptions of reports offered to the user"
(Draheim and Weber 2005, pp. 210, 224). Here both types are made of the
model's fact types: the submission is a population of the form's
subschema for one object (Halpin and Weber 2012), the report a query's
answer.

Every outline of kind Form either is well formed, and then means exactly
one form and is translated by exactly one rule below, or is not, and then
it is refused where it is drawn (the Queries window marks the node, `ormtool
check` fails) and never generated.

### Where a node is

Each node's place is decided from the steps above it, before its mark:

- **The anchor**, the outline's root: the object the form makes or changes.
- **Owned**: an entity node, reached by a step that is not a subtype step
  from the anchor or another owned object, that is neither marked nor
  given, and that has something entered beneath it (not under a
  reference). It is made, changed and put back with the anchor.
- **Referenced**: any other entity node below the anchor: one entered (a
  choice), given, shown, or unmarked with nothing entered beneath. The form
  does not make or change it.
- **A part**: a node reached by a subtype step is the same object as the
  one above it, of that subtype.
- **Absorbed**: a value object the mapping keeps in its owner's row
  (Money, Volume, Distance): not an object of the store, its parts its
  owner's properties.
- **To one, to many**: a step is to one when the role it leaves from is
  unique (a uniqueness constraint spans it alone), else to many.

### What each node means (well formed)

| | The node | Means | Translated to |
| --- | --- | --- | --- |
| D1 | the anchor | the object made (not given) or changed (given) | the instance's root; its key the first element, `role` "key" |
| D2 | given (`= ?`), on a path of steps to one from the anchor | a parameter: its value comes with the form as it opens | an element filled as it opens, `role` "given"; a parameter of the reads and the choices |
| D3 | an entered value, on the anchor, an owned object or a part of either, to one | a fact the submission asserts | an element written by the save, `role` "entered", typed by its attribute |
| D4 | an entered entity, on the anchor, an owned object or a part, to one | a choice: the object the fact is about is picked, not made | an element holding the chosen object's key (`kind` reference), its choices a query of their own |
| D5 | unmarked steps beneath a choice, leading to nothing marked | conditions on the choice (the drivers of the vehicle) | the choices query's conditions, on the form's other elements by shared nodes |
| D6 | entered values beneath a referenced object, together the roles of one of its uniqueness constraints (its reference scheme or another) | identification: they find at most one object, which the fact is about | the lookup's inputs, written as the choice's key would be; refused at save when no object has them |
| D7 | a shown node, anywhere a path reaches | read, never written | an element read with the anchor (again when a reference it goes through changes), `role` "shown"; an `output` |
| D8 | a step to many from the anchor or an owned object, with something entered beneath | a repeat of the submission: rows asserted, each item made, changed or deleted with the anchor | a repeat: each row a form of the same rules, anchored on the item and given its owner back |
| D9 | a step to many with only shown nodes beneath, from anywhere | a list in the report | a read-only repeat: rows read, never written |
| D10 | a unary, on the anchor, an owned object or a part | a flag asserted (entered) or read (shown) | an `xsd:boolean` element at its owner's path |
| D11 | an absorbed value, wherever its owner may be | its parts, whole or not given | an element per part at its owner's path (`volumeQuantity`, `volumeVolumeUnit`) |
| D12 | a part (subtype step) | its nodes count where the object is of that subtype | on the anchor or an owned object: a kind element choosing it, its elements `relevant` where chosen; on a referenced object: shown where it is one |
| D13 | a computed value (`X = expr (shown)`) over nodes at its own level or above by steps to one | a value worked out from the form's values | an element `calculate`d, read-only; also worked out by ORMRuntime when it reads the form |
| D14 | a computed value whose operand is beneath a step to many, under an aggregate (count, total, avg, max, min) | an aggregate over the rows | `calculate` over the repeat's or list's rows (`sum(purchaseLines/amount)`); ORMRuntime the same |
| D15 | a constraint or rule whose roles are all in the form | checked as the form is filled in | a bind (see [Binds](#binds-the-constraints-that-apply)) |
| D16 | any other constraint or rule on the form's fact types | checked where the submission is saved | `checkedWhereSubmitted`, refused in its words at its element |

### What is no form (refused where it is drawn)

| | The outline | Why |
| --- | --- | --- |
| E1 | entered values beneath a referenced object that are not the roles of one of its uniqueness constraints (a van's colour, part of a compound key) | they identify a set of objects at best, not one: no fact can be about it |
| E2 | anything entered beneath a referenced object but a choice's own identification (D6): beneath a given, shown or passed-through object, or a step to many from one; a unary entered on one | the form would change objects it does not own |
| E3 | given beneath a step to many | a parameter is one value, not one per row |
| E4 | a computed value with an operand beneath a step to many, not under an aggregate | one value from many rows needs an aggregate |
| E5 | a computed value with an operand in a choice's conditions (D5) | conditions are not read; there is no value to compute with |
| E6 | an unmarked node, or unary, that leads to nothing entered, shown or given, that no value computes with, and that is not beneath a choice (a condition is only ever a choice's) | a form asserts, identifies, chooses or shows; a bare step does none of these |
| E7 | a node the mapping places nowhere: a read of the anchor and the node, by the steps between them alone, has no column for it (a compound's part is placed with its compound) | the store cannot hold it; the mapping is to be changed, not the form trimmed |

`ORMFormDefinition` gives each node its place and its rule. A rule broken
is said at its node in the Queries window ("This outline is no form: E6:
Station: ..."), makes `ormtool check` exit 1 with a line for each, and
`ORMFormDocument` refuses the outline.

A well-formed outline the generator cannot translate is the generator's
fault, and an error: `ormtool xforms` names the node, writes nothing for
that form, and exits 1 (`missing` in `ORMFormDocument`). It is never a form
without the node.

A choice found by its key (D6, an order's customer by email) has no list
of choices: the key's values are its controls, entered, and the app finds
the object as they are entered and again as the form is saved
(`form:identify/<name>`, a read of the chosen type with the values as its
parameters); none found, the save is refused at the first of them ("There
is no Customer with that Email."). What is required of the choice is
required of them.

### Where the generator is now

Written down, the definition shows what the generator does not do yet,
each with the rule it falls short of; each is an error where it is met,
never a form without it:

- D8 for rows that are facts of many rather than objects of one owner (a
  driver's vehicles, entered): reported missing ("rows entered that are
  not each of one User, but facts of many"); read as a list (D9), they
  are made.
- A list read through a reference (D9, the driver's vehicles) is read as
  the form opens and with its object; a session does not read it again
  when the reference changes, as it does a value shown through it.
- In the XForms document, what is shown through a reference, a choice's
  key's object (D6) and its reads are the app's to fill in (its answers to
  `form:read` and `form:save`): the document does not read them again as
  the reference changes.
- A form under construction is said so (`ormtool contract`); nothing at
  run time refuses to open it, the copy being the app's own.
- A form's further anchors are set by its outline's header (`, with ...`)
  or `-setWithForms:ofQuery:reason:`; the Queries window has no control of
  its own for them.
- A task done with a flow's entry (`ormkit:flow:`) is given the task's
  variables for the application's view; WorkflowKit does not open the
  entry's first form itself.

### Sources

- Dirk Draheim and Gerald Weber, "Modelling form-based interfaces with
  bipartite state machines", *Interacting with Computers* 17 (2005)
  207–228: submit/response interaction, the form as an editable method
  call, typed pages (reports) and server actions (inputs).
- Dirk Draheim and Gerald Weber, *Form-Oriented Analysis: A New
  Methodology to Model Form-Based Applications*, Springer, 2005: the
  method, formcharts, their data model and dialogue constraints.
- Terry Halpin and Gerald Weber, "Form-and-Fact Based Modeling",
  EMMSAD 2012, LNBIP 113, pp. 285–299: fact-based modelling for the data,
  form-based for the interface, screen transition diagrams. We have its
  abstract, not its text.
- Anthony Bloesch and Terry Halpin, "ConQuer: A Conceptual Query
  Language", ER '96, LNCS 1157, pp. 121–133; "Conceptual Queries using
  ConQuer-II", ER '97, LNCS 1331, pp. 113–126: the outline of paths
  through fact types a form is written as, and its aggregates.
- Terry Halpin and Tony Morgan, *Information Modeling and Relational
  Databases*, 2nd ed., Morgan Kaufmann, 2008: reference schemes and
  uniqueness constraints (D6, E1), absorption by the relational mapping
  (D11).
- Amir Choobineh, Michael V. Mannino, Jay F. Nunamaker and Benn R.
  Konsynski, "An Expert Database Design System Based on Analysis of
  Forms", *IEEE TSE* 14(2), 1988, 242–253; Choobineh, Mannino and Tseng,
  "A Form-Based Approach for Database Analysis and Design", *CACM* 35(2),
  1992, 108–120: the other direction,
  a schema derived from forms; we have their abstracts, not their text.

## What a form gives

### The instance

The form's tree is mapped to an XML instance, as Rmap maps a schema to
tables ([COREDATA-MAPPING.md](COREDATA-MAPPING.md)), but to one tree. The
names are the mapping's properties (Core Data's; the service's as
ODataKit's `ODataPropertyMapper` says them), so the instance is the
entity's own representation, the same whether a store or the service
holds it.

| In the form | In the instance |
| --- | --- |
| the anchor | the document element, named as its entity; its key the first element |
| a value, functional | an element named as the attribute (`litres`), typed: `xsd:decimal`, `xsd:date`, `xsd:dateTime`, `xsd:boolean`, `xsd:string` |
| a compound value the mapping absorbs (Money, Distance) | its parts as absorbed (`moneyAmount`, `moneyCurrency`): whole or not given |
| a unary | a flag, `xsd:boolean` (`filledTheTank`) |
| a reference | an element holding the key of the object chosen (`driver`), its choices an instance of their own |
| a value through a reference | an element named by its keys (`purchaseOrderSupplierContactContactName`), read with the anchor and again when the reference changes |
| an owned object | a group of elements, nested (`contact/shippingAddress/city`) |
| a subtype part | its elements (`tripMoment` where another part has a `moment`), and an element `isA` saying the kind |
| a step to many | a repeat: each item a row of a form of its own |
| a given node | an element filled as the form opens |
| a value node | an element calculated |

**Owned objects** (a customer's contact, the contact's shipping address)
are made with the anchor where every anchor has one (`needed`) or where
anything of them is entered, changed with it, and put back with it when
the save is refused; to a service they are nested in the body (a deep
insert, a deep update).

**Subtype parts:** a new object is made of the kind chosen, one read is of
its kind and stays so, and the service is told its type (`@odata.type`).
A part's rows (a service's lines) are a repeat relevant where the object
is of it, written to the store and sent to the service only then. The
form read as a query (its sentence, its plan, its results in the Queries
window) reads each part and what is beneath it as "maybe": every object,
each with its own part's values, not those that are of every part.
The kind's choices are labelled as a reader says the subtype's name ("Fill
up" for FillUp).

**Repeats:** a step from the anchor to many (an order's lines) is a form
anchored on what it reaches, given the anchor by the same fact type the
other way round. In the document its rows are elements of the anchor's,
named as the repeat (`purchaseLines`), shown in an `xf:repeat`, each with
a trigger taking it away and one after them adding a row from an instance
of one empty row (`row-purchaseLines`); a row's binds are at its path
(`purchaseLines/quantity`), its references' choices their own
(`form:choices/purchaseLines/stockItem`). An aggregate over the rows (D14,
`Wanted = total(Quantity) for PurchaseOrder`) is calculated over them in
XForms 1.1's terms (`sum(../purchaseLines/quantity[. != ''])`, `max()`,
`count()`), and worked out by `ORMForm` from the rows it reads or is given,
not read.

**Beyond the anchor:** rows beneath an owned object (a contact's phones,
`contact/phones`) are written into it with the anchor, linked by the
owned object's key, an element of its group (`contact/id`); rows beneath
what the form refers to (the driver's vehicles, `driverVehicles`) are a
list, read for the reference's key, never written. The anchor's save writes each row into its item, found or
made and linked; an item the rows no longer have is deleted; a row's
refusal is said at `purchaseLines[1].quantity`.

**Submitted, not saved:** a process's task may be done with a form whose
values a procedure takes (goods received: a receipt and its moves).
`ORMFormSession`'s `submitting` hands the values to whoever submits them
and takes back what it refuses and what it made.

### Binds: the constraints that apply

A constraint is a bind when all its roles are in the form, its alert the
constraint's own statement; the bind names it in `ormf:constraints`.

| ORM | Bind |
| --- | --- |
| mandatory role (simple) | `required="true()"`; in an owned object that need not be, once anything of it is entered (`../* != ''`) |
| the definition of a subtype the anchor is of ("Each MeteredEvent is by definition an Event that was at some Distance") | `required`, the definition its alert |
| inclusive-or | `required` on each while the others are empty |
| value range, text length | `constraint` |
| a list of values | the `select1`'s items |
| exclusion, exclusive-or | `relevant` while the others are empty |
| subset | the first `relevant` where the second is given |
| equality; a compound value | `required` each where the other is given |
| value comparison | `constraint`, compared when both are given |
| a value node's expression | `calculate` (`number(../totalAmount) div number(../volumeQuantity)`), empty until its operands are given |
| deontic | XFormsKit's `xfk:warning`: shown at its element, never invalid, never in the way of a submission |
| a rule over the form's own values ("It is impossible that: FillUp + was of Volume + has Quantity > 200") | `constraint` at the first of them entered: `not(../volumeQuantity != '' and number(../volumeQuantity) > 200)`; deontic, a warning |
| a derived fact type shown (a unit price, its derivation over the cost and the volume) | `calculate`, as the derivation says over the form's elements; where the read cannot take it (its derivation branches), read on its own by the key |

An owned object's and a subtype part's constraints are bound as the
anchor's are, each path from the element's own place
(`../../../contact/shippingAddress/postCode`). Constraints on a
supertype's roles about another of its subtypes (a trip's, in a fill-up's
form) are left out.

A rule is a bind where each of its steps is one of the form's, through
the same fact type and role, from the anchor (a compound's parts, which
the outline need not list, among them), its conditions comparisons of
them. What a form cannot check alone (a join, a pattern, uniqueness across
objects, a rule through facts it does not hold: the driver who drives the
vehicle, the meter going up) is listed under `ormf:checks` as
`ormf:checkedWhereSubmitted`, in words, and checked where it is saved.
Either way a constraint is met as an error said in the model's words, or
the app's: `ormtool xforms ... --messages file.plist` (texts by constraint
or rule name or id, `ORMFormDocument.messages`) says them in its alerts and
checks, and `ORMForm` where the store refuses one.

### Controls

Intent only, in the outline's order: an `input` for an entered value, a
`select1` for a reference or a list of values, a `group` for a compound,
an owned object or a subtype part, an `output` for what is shown or
calculated. The label is the role's name, else its player's (a unary's,
its reading); the hint, the fact type's note; the alert, the constraints'
statements. A given node has no control. Ids come from the model element
(`control-<node id>`, `bind-<node id>`), so a renamed role or a reordered
outline keeps them.

### In and out: a service or a local store

A form does not say where its data is. Its reads and save are planned from
the same tree as any query is ([QUERIES.md](QUERIES.md)), and the app says
where they run:

- **The service.** Reads are OData requests (`$select`, `$expand`), a
  repeat's rows one of their own; a new object is a `POST` (with its owned
  objects and its rows, a deep insert), an existing one a `PATCH` of what
  changed with `If-Match`, its rows a delta (`PurchaseLines@delta`: those
  added or changed, those taken away `@removed` as deleted); references
  as `@odata.bind`. Tried against ODataKit's `ODataService` over a store.
- **An action.** A form may be submitted to an action of the service's
  instead of saved (`ormtool xforms ... --action ReceiveGoods=ReceiveGoods`,
  `ORMFormDocument.action`): its save is `form:submit/<Action>`, a `POST` of
  the action with the anchor's entity as its one parameter
  (`{"PurchaseOrder": {...}}`, as a new one would be sent, its rows
  within), and the action's answer the key of what it did.
- **The local store.** Reads are fetches run by the interpreter; a save
  writes the instance into objects, by the same mapping, and saves the
  context: Core Data's checks, the generated validation code and the rules
  at save ([COREDATA-MAPPING.md](COREDATA-MAPPING.md#validation-code-what-core-data-cannot-enforce),
  [RULES.md](RULES.md)) refuse it as the service would. Sync uploads it
  later.

In the document, each read and the save is a name the app resolves
(`form:read`, `form:choices/<name>`, `form:save`) through its XForms
submission transport. Each reference's choices are a query of their own,
read when the form opens and again when what they depend on changes. A
refusal comes back by element (the service's error details by target, or
`NSValidationKeyErrorKey`) and is shown at its control; deontic
violations come back as warnings.

An app runs a form without ORMKit: ORMRuntime's `ORMForm` reads the
`<Form>.ormform` table ormtool writes beside the document
([RUNTIME.md](RUNTIME.md#forms)), and `ORMFormSession` holds the values,
the choices and the refusals for any view of it.

### Customizing: the contract, and the views of it

A generated form reads like the model, not like the app, and people lay
forms out, word them, and build their own. What has to hold is not how a
form looks but what goes in and out of it. **A form is a contract**, and
its table holds it:

- **its inputs:** what it is given as it opens (`-inputNames`);
- **what is entered and shown:** each element's `role` ("key", "given",
  "entered", "shown", "calculated", "hidden") and `label`;
- **what it may offer:** each reference's choices and what they depend on;
  an element's `items` (and `itemLabels`), where the model lists its values;
- **its groups:** each owned object's keys, entity, key, and whether it is
  `needed`;
- **what a save writes, and its result:** the object saved, its key;
- **the rules:** the model's, checked as it is filled in where they can be
  and always where it is saved.

Flows and processes refer to a form only by its contract. Its views:

1. **The generated XForms document**, the default, replaced whole when the
   model changes.
2. **A customized copy of it**, kept with the app's sources and edited
   freely. The build checks it against the contract (`ormtool contract
   model.orm Form copy.xhtml`, `ORMFormCustomization`): an input it does
   not take, an element the contract has not, or one the contract enters
   that it never binds, is an error; a looser bind is a warning.
3. **A view of the app's own:** a XIB's controls bound to the session's
   values, its pop-ups filled from the choices, the refusals shown at its
   controls.

**A form under construction does not run.** A field the model has no fact
type for has nowhere to go, so a customization that adds one marks it
(`ormf:provisional="true"` on its instance's element) and its form is under
construction, which `ormtool contract` says, until the model has the fact
types it asks for. Each provisional field is a question for the modeller,
and **seeds the model**: `ormtool propose model.orm Form copy.xhtml
[sample.xml]` says the fact types they ask for as FORML (`ormtool apply`
takes it), each a value type, typed by its bind or by the values a sample
filled in has, the anchor's fact type with it (one each, exactly one where
the copy requires it, its values where the copy lists them), a flag a
unary, and the step the form is to have:

```
Colour is a value type.
Portable data type: Text: Variable Length
The possible values of Colour are 'red', 'white'.
FillUp has Colour
Each FillUp has exactly one Colour.
// in the form: + has Colour (entered)
```

## The flow vocabulary

A flow is what a design tool's prototype is, in the model's terms:

| Figma | A flow |
| --- | --- |
| a frame | a **screen**: a form, or a list (a query whose rows lead somewhere) |
| a connection, on a click | a **transition**, on an action: `RowChosen`, `Trigger` (a control of the form), `SubmitDone`, `SubmitError`, `Cancel` |
| what the next frame shows | what the transition **gives** the next form: its given nodes, from the row chosen, what the screen saved, or a value a screen before had |
| navigate, overlay, back | its **kind**: navigate; overlay (a modal form over this one); back; close the overlay, giving the form under it what it made |
| a flow's starting point | an **entry**: where the app, or a task, begins |

A flow is one file, XML in ORMKit's own namespace, naming its model and
referring to its forms and queries by id, their names beside for a reader;
one the model no longer has is reported:

```xml
<flow:Flow xmlns:flow="http://schemas.ormkit.org/2026-10/Flows" Name="Fleet" Model="Fleet.orm">
    <flow:Entry Name="Start" Screen="Vehicles"></flow:Entry>
    <flow:Screen id="Vehicles" Query="_5D996639-D799-471F-962E-3877A50A854A" Name="Vehicles" X="0" Y="0" Width="390" Height="844"></flow:Screen>
    <flow:Screen id="RecordFillUp" Form="_8A69A360-C738-4C55-8542-F1A8EA7184D9" Name="RecordFillUp" X="480" Y="0" Width="390" Height="844"></flow:Screen>
    <flow:Screen id="NewStation" Form="_8A4C9725-696A-4BCD-8DE7-D19CF6B57D10" Name="NewStation" X="960" Y="0" Width="390" Height="844"></flow:Screen>
    <flow:Transition From="Vehicles" On="RowChosen" To="RecordFillUp">
        <flow:Give Node="_8C6710B8-2CDB-4AFE-9F4D-659658AEABED" From="row"></flow:Give>
    </flow:Transition>
    <flow:Transition From="RecordFillUp" On="SubmitDone" Kind="Back"></flow:Transition>
    <flow:Transition From="RecordFillUp" On="Cancel" Kind="Back"></flow:Transition>
    <flow:Transition From="RecordFillUp" On="Trigger" Control="newStation" To="NewStation" Kind="Overlay"></flow:Transition>
    <flow:Transition From="NewStation" On="SubmitDone" Kind="Close">
        <flow:Give Node="_287EFCB3-73AA-41B1-A5B8-CFABD1F38F03" From="result"></flow:Give>
    </flow:Transition>
    <flow:Transition From="NewStation" On="Cancel" Kind="Close"></flow:Transition>
</flow:Flow>
```

(An excerpt of [Samples/Fleet.flow](../Samples/Fleet.flow). A `Give`'s
`Node` is a given node of the next screen's form; `From` is `row` (the
list's row chosen), `result` (what the screen before saved), or
`<screen id>.<node id>` (a value a screen before had).)

What is inside a screen is not in the flow: a form's controls, and where
they are, are the form's and its customization's. A flow draws each screen
from them and keeps no copy.

## Flows: what they give

**Generated into the forms.** In XForms a transition is what a
submission's `xforms-submit-done` or `xforms-submit-error`, or a trigger's
`DOMActivate`, does: an `xf:load` of a resource the app resolves. The
forms themselves do not name each other; `ormtool xforms model.orm dir/
--flow Fleet.flow` writes each screen's form with its ways on:

| Resource | Where it goes |
| --- | --- |
| `form:open/<Form>?<element>=<value>&...` | the next form, its given elements; over this one (`show="new"`) for an overlay |
| `form:list/<Query>` | the next list |
| `form:back` | the screen before |
| `form:close?<element>=<value>&...` | the overlay closed, the values given to the form it is over |

**Played before an app exists.** `ORMFlowWalk` runs a flow over the
model's sample population ([POPULATIONS.md](POPULATIONS.md)), in a store
made of it, as an app would: a list's rows are its query's, a form opens
with what the way to it gave, its choices are the population's, and a save
is checked and refused in the rule's own words. A domain expert clicks
through with real-looking facts, and what they ask for that the model
lacks is found there, not in production. `ormtool flow model.orm
Fleet.flow walk` walks each way once and prints what happened:

```
▶ Start: Vehicles, 2 rows: KZ 101 AAA | KZ 202 BBB
Vehicles —RowChosen (KZ 101 AAA)→ RecordFillUp, given vehicle = KZ 101 AAA
RecordFillUp refused: litres: Each FillUp took exactly one Litres. The possible values of Litres are {(0..]}.; moment: Each FillUp was at exactly one Moment.
RecordFillUp —Trigger newStation→ over it: NewStation
NewStation refused: stationName: Each Station is called exactly one StationName.
NewStation —Cancel→ closed: RecordFillUp
RecordFillUp —Cancel→ back: Vehicles
```

**Drawn on a canvas of its own**, not the model's diagram: a `.flow` opens
in its own window (ORMDesigner) or tab (UDCode), with the model it names.
The model's forms and lists are placed as screens, drawn with their
outlines; transitions are arrows from a screen or a control to a screen;
entries are marked. **Play** walks it in a window: the screen it is at,
what it shows (a list's rows; a form's elements, each entered with the
control its type wants: a date's picker, a flag's checkbox, a reference's
choices named as a reader knows them), the ways on, and what happened.

**BPMN** sees the same from the process's side: a user task is performed
with a form or a flow, its input data the entry's given nodes, its output
what was submitted. A flow is one actor's dialogue; a process is who does
what, in which order, across actors. In WorkflowKit a task's form key is
`ormkit:form:<Form>` or `ormkit:flow:<file>#<entry>`; the form's document
(`<Form>.xhtml`, as `ormtool xforms` writes it) deployed beside the process
is the task's, and WorkflowKit's `WFModelFormHandler` fills its given
elements (each bind says its element's role, `ormf:role`) from the task's
variables and sets a variable of each element submitted, a repeat's rows
an array.

### Figma

No standard covers what Figma does; the nearest is OMG's IFML (view
containers, events, navigation flows bound to a domain model), a check on
our terms whose format we do not use. A flow keeps a small subset of what
a design tool does:

| Kept | Not kept |
| --- | --- |
| a screen: its place and size, the form or list it shows (or a placeholder) | drawing: vectors, styles, effects, images, fonts |
| a transition: from a screen or a control, on an event, to a screen | auto layout, constraints, variants, components |
| its kind: navigate, overlay, back, close | animations |
| what it gives the next screen; entries | comments, versions, collaborators |

**From Figma** (planned), through its REST API (`GET /v1/files/:key`),
which reads prototypes and writes no frames: a page's
`flowStartingPoints` are entries; a frame with our id, or named as a form
or query, is that screen, any other a placeholder; a layer named as a
control is that control; `ON_CLICK` with `NAVIGATE` or `SWAP` is a
transition, `OVERLAY` an overlay, `BACK` back, `CLOSE` a close; what
happens within a frame (`SCROLL_TO`, `CHANGE_TO`, hovers) is not kept. A
layer that looks like a field and names nothing the form has is a
provisional field.

**To Figma** (planned), through a plugin of our own, since only the Plugin
API makes frames: each screen a frame with its form's controls as
labelled placeholders, each transition a reaction (`setReactionsAsync`),
the entries the page's starting points, and each element's id kept with
`setSharedPluginData` (namespace `ormkit`), so the next import matches by
id, not by name.

## Running one

Anything that runs XForms runs a generated form: XFormsKit's views,
XSLTForms in a browser. For a native UI laid out by hand (a XIB, an iOS
storyboard), XFormsKit's processor runs without its views and each native
control is the view of an `XFControl`, showing its value and state and
committing what is typed. XFormsKit still needs decimal arithmetic for
`xsd:decimal` (XPath 1.0's numbers are doubles: 0.1 + 0.2 is
0.30000000000000004) and a refresh of only what changed.

## Commands

- `ormtool xforms model.orm dir/ [form] [mapping] [--flow file.flow]
  [--action Form=Action]... [--messages file.plist]` writes each form's
  `<Form>.xhtml` and `<Form>.ormform`, never edited, and prints what it
  leaves to its submission and the plans `form:read` and each
  `form:choices/<name>` stand for; a form that breaks a rule of the
  definition, or that lacks an element the model has in it, is not written
  and makes it exit 1.
- `ormtool check model.orm` checks each form too: each rule of the
  definition broken, and each element it would lack, a line, exit 1.
- `ormtool contract model.orm Form copy.xhtml` checks a customized copy
  against the form's contract; `ormtool propose model.orm Form copy.xhtml
  [sample.xml]` says the fact types its provisional fields ask for.
- `ormtool flow model.orm file.flow` lists a flow and what is wrong of it;
  `... walk [entry]` walks it over the sample population.

## Planned

- Figma import and export.

## Open questions

- **Where the Figma plugin lives.** A plugin is TypeScript, built and
  published apart: a repository of its own.
- **The paper itself.** What is taken from it here comes from its abstract
  and summaries; the full text may say otherwise.
