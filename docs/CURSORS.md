# Cursors

How a query plan is read: compiled to a tree of cursors, each of which
gives the next batch of what it reads and can be asked for more. Both
backends share the tree. Core Data (`ORMQueryInterpreter`) and OData
(`ORMQueryOData`) differ only in the leaves, and in how each evaluates a
condition on its own objects. [QUERIES.md](QUERIES.md) has the plans,
[ODATA.md](ODATA.md) the requests.

Steps 1 to 5 below are built (`ORMCursor.h`). "Today" in the tables is
what the code did before them; [Steps](#steps) says what is still to come.

## Why

Today each backend reads a plan its own way, and does the same things
twice:
- **Batches.** The interpreter fetches slices; the OData cursor fetches
  pages.
- **Narrowing to a batch.** Bags are read for a batch's groups only. Joins
  are read for a batch's values only: the interpreter probes, OData uses
  page joins and narrowed joins.
- **Rows.** Each makes a batch's rows while that batch's bag rows are still
  current. The OData cursor once made them after the next batch had
  replaced the bag rows, and gave wrong rows.
- **No row twice.** Each keeps every row it has given, so memory grows with
  the result.
- **Paging by offset.** `fetchOffset` and `$skip` rescan what came before,
  and drift when the data changes between pages.

All of these are properties of the reading, not of either backend. Here
they are done once, as operators, in the iterator model (Graefe, "Volcano",
1994). Each `next` returns a batch rather than a row, as in MonetDB/X100.

Dataphor works the same way: a D4 table expression compiles to plan nodes,
and running it opens a cursor on them. The cursors' capabilities (ordered,
keyed, bookmarkable) say what a consumer may ask of them.

## The protocol

```objc
@protocol ORMCursor <NSObject>
- (void)next:(NSUInteger)count completion:(void (^)(ORMBatch *batch, NSError *error))completion;
@property (nonatomic, readonly) BOOL atEnd;
/* What reading it does, to read: the program text. */
- (NSArray<NSString *> *)programLines;
@end
```

It is asynchronous, because the service answers on the transport's queue.
A Core Data leaf calls its completion before `next:` returns. So the
synchronous `-[ORMQueryCursor nextPage:error:]` runs the tree and has its
answer, without waiting on a semaphore and without leaving the context's
queue. A completion that has not been called on return is an error there.

`count` asks for up to that many objects. A cursor may give fewer before
its end (a filter drops some), even none: a Filter that drops a whole
batch gives an empty one. Only `atEnd` says the end; the Page reader and
`-[ORMPlanRun next:]` read on until it, or until a batch keeps something. As in Reactive
Streams' `request(n)`, the consumer asks for more, and nothing is read
ahead of what it asks for.

## The batch

```objc
@interface ORMBatch : NSObject
@property (nonatomic, copy) NSArray *objects;
@property (nonatomic, copy) NSDictionary<NSString *, id> *answers;
@end
```

- **objects:** what is read, as the backend has it. That is managed objects
  for Core Data, and `ORMODataObject`s (JSON and their entity) for OData.
- **answers:** what was read for this batch, by name. A bag gives its
  tuples, grouped by group. A join gives its objects, or the values it
  found.

Every condition and every row of the batch is evaluated against its own
answers. A later batch can never change an earlier one's rows, because
answers belong to a batch, not to the cursor.

## The operators

| operator | does | today |
|---|---|---|
| **Scan** (request, order, resume) | reads the entity's objects the request filters, in order, a batch at a time. The only leaf, and the only node a backend builds alone | the fetch in slices (`ORMPlanRun -next:`); the OData GET with `$top`/`$skip` |
| **Prefetch** (inner plan) → Scan's arguments | reads an uncorrelated join once, before the first batch; its values become arguments of the Scan's filter | `joinPrefetchLimit` fetch; OData `joins` / `-filterJoining:` |
| **BindJoin** (input, inner plan, scope) | for each batch of the input, reads the inner plan once, narrowed to the batch's values (the scope), and puts what it found in the batch's answers. Without a scope, the inner plan is read once, whole, and every batch shares it | bags per slice / page; page joins; narrowed `wholeJoins`; the interpreter's probe per object (now per batch) |
| **SemiJoin** (input, BindJoin's answer, pairs) | keeps the batch's objects whose values the answer has | OData page joins without a check (`groupby`) |
| **Filter** (checks) | keeps the objects meeting the conditions the request could not say, evaluated on the batch with its answers | `checks`; `_checks` / `-keeps:` |
| **Rows** (columns) | turns a batch's objects into tuples, a tuple per way the conditions bind, evaluated with its answers | `-rowsOf:` in both |
| **Distinct** | no tuple twice | the `given` sets |
| **Page** | the root: asks its input until it has the page's objects or the input is at its end; gives an `ORMQueryResult` | `nextPage:` in both |

A plan reads as a pipeline, outermost last:

```
Page(Distinct(Rows(Filter(BindJoin(BindJoin(Scan Branch, bag1 for nr), join1 for city parts)))))
```

### What a BindJoin's scope is

A **scope** is the values of the batch the inner plan is narrowed to.
- For each value, it names our path (from the object read) and the inner
  plan's path that must equal it. An entity's value is compared by its key.
- The inner plan is read with "one of these tuples" added. For Core Data
  that is `IN` or an `OR` of `AND`s in the predicate. For OData it is the
  same in `$filter`.

The values must be the object read's, or reached from it through to-ones.

A value bound inside a `some` (a lambda's variable, a group under a
to-many) is not one the batch names. That inner plan has no scope, and is
read whole once. The program text says so.

This is a **bound join** (Haas et al., Garlic; Schwarte et al., FedX
2011): a remote source that can only be probed, probed once per batch with
the batch's bindings. The general idea is sideways information passing
(Ives and Taylor, 2008).

A **correlated join** is an Apply in the sense of Galindo-Legaria and Joshi
(2001): its inner plan depends on the outer object. A BindJoin gives each
batch its candidates, and the Filter evaluates the correlation per object,
with the object bound.

### Distinct without keeping every row

Rows of different objects read can be the same tuple only if the columns
leave out what tells the objects apart.
- **When the object read is listed by its identifier,** no tuple of one
  object is another's. Distinct need only compare an object's own tuples,
  and keeps nothing between batches.
- **When the input is ordered by the listed values,** equal tuples are
  adjacent, and Distinct keeps only the last.
- **Otherwise** it keeps every tuple given, and the program text says so.

## Capabilities

Each cursor says what it can do, as Dataphor's do:
- **ordered:** in a total order; the plan's sorts, then the key.
- **keyed:** each object has a key that is unique and in that order.
- **resumable:** it can start after a given key (a bookmark) instead of
  after a number of objects.

A Scan over a keyed, ordered entity is resumable. Its next batch is read
after the last key it gave: `nr > 52`, or `(name, nr) > ('Ann', 7)` written
out with `OR` and `AND`, in the predicate or `$filter`. This is the "seek
method" (Winand, *Use The Index, Luke*). It does not rescan what came
before, and a change between batches neither skips nor repeats an object.

A Scan that is not resumable pages by offset, as today. A Scan follows the
service's `@odata.nextLink` when the service pages for itself.

## What each backend supplies

A **source** builds the leaves and the inner reads:
- a Scan for a plan, its order and its resume point;
- the same narrowed to a scope.

What the store or the service can say is pushed into the request, and the
rest becomes the Filter's checks. That lowering stays where it is
(`-lower:` in each backend).

An **evaluator** evaluates on its objects, given a batch's answers:
- whether a condition holds of an object, its variables bound;
- the ways it binds;
- a path's values.

Core Data's evaluator is key-value coding over managed objects. OData's is
`ORMODataRows` over JSON. Bag lookups and `matches` read the batch's
answers instead of state kept on the run or the request.

The public API does not change: `ORMQueryCursor`, `ORMQueryODataCursor`,
`-executePlan:…`, `-programForPlan:…` and `-requestText`. Only what they
run underneath does.

## Steps

1. **Done: the operators and the batch,** with the interpreter running on
   them. `ORMBatch`, `ORMFilterCursor`, `ORMBindJoinCursor` and
   `ORMPageReader` are shared. The interpreter's leaf is `ORMStoreScan`;
   its bags are BindJoins, and its checks a Filter. Rows and no-tuple-twice
   are the Page reader's, as before.
2. **Done: OData on the same operators.** The leaf is `ORMODataScan`, page
   joins are `ORMODataSemiJoin`, and bags and correlated joins are
   BindJoins, scoped or whole. The two cursors' copies of the batch logic
   are gone.
   - Prefetch stays inside each leaf, by design (step 5).
3. **Done: resumable Scans.** `ORMSeek` orders by the plan's sorts and then
   the entity's key (ODataKit's property mapper says which attributes it
   is). A batch starts after the last one's values.
   - Both scans read this way: `ORMStoreScan` in the predicate and
     `ORMODataScan` in `$filter`, with the key added to `$orderby`.
   - Nothing (null) is less than any value: first ascending, last
     descending. This is how Core Data's SQLite store and the OData spec order
     it; FreeCoreData's stores do the same. So "after" reaches nulls too:
     - descending after x: `a < x`, or `a` is null, where `a` can be null
       (`+[ORMSeek canBeNull:from:]` asks the entity);
     - after a null: ascending, `a` is not null; descending, nothing more
       of `a`, so the next part of the order decides.
   - A scan falls back to offset for an entity with no key. OData also falls
     back when an order attribute is no plain literal (a date, a GUID). By
     offset, the key still comes last in the order, so objects the sorts
     tie on come in one order across pages.
   - A service that pages its answers itself (a next link with fewer than
     asked for) has not ended: the scan reads on after the last one.
   - `testASortByWhatMayBeNothingLosesNoRows` sorts descending by a branch
     most employees head none of, two at a time, from the store, from the
     service, and from a service that sends one object a page.
   - `testPagesResumeAfterTheLastKey` hires someone between pages, numbered
     before the bookmark. Neither backend repeats or skips anyone; by
     offset, both would.
4. **Done: Distinct without keeping every row,** where the rows list the
   object read (`-[ORMQueryPlan listsTheObjectRead]`).
   - The Page reader's `objectsApart` then compares an object's rows with
     its own only, and keeps nothing from one object to the next.
   - Where the rows come in their own order, `rowsInOrder` keeps only the
     last object's rows: equal rows are of objects one after another.
     - Each backend asks `-[ORMQueryPlan rowsFollowOrder:key:]` of the order
       its scan really reads in: the sorts and then the key, or the sorts
       alone by offset.
     - The test is that a prefix of the order determines the rows and they
       determine it. Every column must be a value of the object read (no
       variable's). A listed object's identifier determines what is reached
       from it through to-ones, and the whole key determines everything.
       This is order optimization with functional dependencies (Simmen,
       Shekita and Malkemus, 1996).
   - A plan with no sorts of its own that lists only such values (not the
     object read) is sorted by them by the planner, as D4 reads a table by
     its key. Its rows then always come in their own order.
   - Otherwise it keeps every row given, as before.
5. **Done: the interpreter's probes as BindJoins.**
   - A join the checks would probe object by object is read once for each
     batch, when its pairs' values are the object read's. Only its plan's
     conditions that depend on nothing outside it are read, with its parts
     one of the batch's tuples.
   - Each object is then checked against those candidates in memory, with
     itself bound. `testACorrelatedJoinIsReadForEachBatch` covers this.
   - A join whose pairs come from a `some`'s member is still probed for each
     object.

   **Prefetch stays in the leaves.** The joins made first are resolved
   before the first batch anyway: in the OData scan's preparation, and in
   the interpreter's predicate lowering. For Core Data, whether a join is
   fetched first at all depends on counting it. Its values become part of
   the predicate, an `OR` of `AND`s that substitution variables cannot say.
   An operator of its own would rearrange the lowering and change nothing a
   caller sees.

## Reading

- G. Graefe, "Volcano — An Extensible and Parallel Query Evaluation
  System", IEEE TKDE 1994; "Query Evaluation Techniques for Large
  Databases", ACM Computing Surveys 1993.
- P. Boncz, M. Zukowski, N. Nes, "MonetDB/X100: Hyper-Pipelining Query
  Execution", CIDR 2005.
- L. Haas et al., "Optimizing Queries across Diverse Data Sources"
  (Garlic), VLDB 1997.
- A. Schwarte et al., "FedX: Optimization Techniques for Federated Query
  Processing on Linked Data", ISWC 2011.
- Z. Ives, N. Taylor, "Sideways Information Passing for Push-Style Query
  Processing", ICDE 2008.
- C. Galindo-Legaria, M. Joshi, "Orthogonal Optimization of Subqueries and
  Aggregation", SIGMOD 2001.
- T. Neumann, A. Kemper, "Unnesting Arbitrary Queries", BTW 2015.
- T. Grust, "Monad Comprehensions: A Versatile Representation for
  Queries", 2003.
- D. Simmen, E. Shekita, T. Malkemus, "Fundamental Techniques for Order
  Optimization", SIGMOD 1996.
- M. Winand, *Use The Index, Luke*: "Paging Through Results" (the seek
  method).
- Reactive Streams, the `request(n)` protocol.
