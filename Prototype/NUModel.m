#import "NUModel.h"
#import <stdlib.h>
#import <time.h>
#if !defined(__APPLE__)
#import <unistd.h>
#endif

static unsigned NURand(void) {
#if defined(__APPLE__)
    return arc4random();
#else
    static int seeded = 0;
    if (!seeded) {
        srand((unsigned)time(NULL) ^ (unsigned)getpid());
        seeded = 1;
    }
    return ((unsigned)rand() << 16) ^ (unsigned)rand();
#endif
}

static NSString *NUMakeUUID(void) {
    return [NSString stringWithFormat:@"id-%08x-%08x-%08x",
            NURand(), NURand(),
            (unsigned)([[NSDate date] timeIntervalSince1970] * 1000.0)];
}

@implementation NUObjectType

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = NUMakeUUID();
        _name = @"Object";
        _kind = NUObjectEntity;
        _referenceMode = @"";
        _valueConstraint = @"";
        _independent = NO;
        _origin = NSMakePoint(40, 40);
        _size = NSMakeSize(140, 56);
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _identifier = [[c decodeObjectForKey:@"id"] copy] ?: NUMakeUUID();
        _name = [[c decodeObjectForKey:@"name"] copy] ?: @"Object";
        _kind = [c decodeIntegerForKey:@"kind"];
        _referenceMode = [[c decodeObjectForKey:@"ref"] copy] ?: @"";
        _valueConstraint = [[c decodeObjectForKey:@"vc"] copy] ?: @"";
        _independent = [c decodeBoolForKey:@"ind"];
        _origin.x = [c decodeDoubleForKey:@"x"];
        _origin.y = [c decodeDoubleForKey:@"y"];
        _size.width = [c decodeDoubleForKey:@"w"];
        _size.height = [c decodeDoubleForKey:@"h"];
        if (_size.width < 40) _size = NSMakeSize(140, 56);
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.identifier forKey:@"id"];
    [c encodeObject:self.name forKey:@"name"];
    [c encodeInteger:self.kind forKey:@"kind"];
    [c encodeObject:self.referenceMode forKey:@"ref"];
    [c encodeObject:self.valueConstraint forKey:@"vc"];
    [c encodeBool:self.independent forKey:@"ind"];
    [c encodeDouble:self.origin.x forKey:@"x"];
    [c encodeDouble:self.origin.y forKey:@"y"];
    [c encodeDouble:self.size.width forKey:@"w"];
    [c encodeDouble:self.size.height forKey:@"h"];
}

- (id)copyWithZone:(NSZone *)zone {
    NUObjectType *o = [[[self class] allocWithZone:zone] init];
    o.name = self.name;
    o.kind = self.kind;
    o.referenceMode = self.referenceMode;
    o.valueConstraint = self.valueConstraint;
    o.independent = self.independent;
    o.origin = NSMakePoint(self.origin.x + 28, self.origin.y + 28);
    o.size = self.size;
    return o;
}

- (NSRect)frame {
    return NSMakeRect(self.origin.x, self.origin.y, self.size.width, self.size.height);
}

- (NSString *)displayName {
    NSMutableString *s = [NSMutableString stringWithString:self.name ?: @""];
    if (self.kind == NUObjectEntity && self.referenceMode.length)
        [s appendFormat:@"(.%@)", self.referenceMode];
    if (self.independent) [s appendString:@" !"];
    return s;
}

- (NSString *)verbalization {
    NSString *kind = (self.kind == NUObjectValue) ? @"value type" : @"entity type";
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@ is a %@.",
                          [self displayName], kind];
    if (self.valueConstraint.length)
        [s appendFormat:@" Value constraint: %@.", self.valueConstraint];
    return s;
}

@end

@implementation NURole

- (instancetype)init {
    self = [super init];
    if (self) {
        _playerId = @"";
        _mandatory = NO;
        _unique = NO;
        _freqMin = 0;
        _freqMax = 0;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _playerId = [[c decodeObjectForKey:@"p"] copy] ?: @"";
        _mandatory = [c decodeBoolForKey:@"m"];
        _unique = [c decodeBoolForKey:@"u"];
        _freqMin = [c decodeIntegerForKey:@"fmin"];
        _freqMax = [c decodeIntegerForKey:@"fmax"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.playerId forKey:@"p"];
    [c encodeBool:self.mandatory forKey:@"m"];
    [c encodeBool:self.unique forKey:@"u"];
    [c encodeInteger:self.freqMin forKey:@"fmin"];
    [c encodeInteger:self.freqMax forKey:@"fmax"];
}

- (BOOL)hasFrequency {
    return self.freqMin != 0 || self.freqMax != 0;
}

- (NSString *)frequencyLabel {
    if (![self hasFrequency]) return @"";
    if (self.freqMax < 0)
        return [NSString stringWithFormat:@"{%ld..n}", (long)self.freqMin];
    if (self.freqMin == self.freqMax)
        return [NSString stringWithFormat:@"{%ld}", (long)self.freqMin];
    return [NSString stringWithFormat:@"{%ld..%ld}",
            (long)self.freqMin, (long)self.freqMax];
}

@end

@implementation NUFactType

static const CGFloat kRole = 28.0;

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = NUMakeUUID();
        _reading = @"... ...";
        _origin = NSMakePoint(80, 80);
        _spanningUnique = NO;
        _ringKind = NURingNone;
        _roles = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _identifier = [[c decodeObjectForKey:@"id"] copy] ?: NUMakeUUID();
        _reading = [[c decodeObjectForKey:@"rd"] copy] ?: @"... ...";
        _origin.x = [c decodeDoubleForKey:@"x"];
        _origin.y = [c decodeDoubleForKey:@"y"];
        _spanningUnique = [c decodeBoolForKey:@"su"];
        _ringKind = [c decodeIntegerForKey:@"ring"];
        _roles = [[c decodeObjectForKey:@"roles"] mutableCopy] ?: [NSMutableArray array];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.identifier forKey:@"id"];
    [c encodeObject:self.reading forKey:@"rd"];
    [c encodeDouble:self.origin.x forKey:@"x"];
    [c encodeDouble:self.origin.y forKey:@"y"];
    [c encodeBool:self.spanningUnique forKey:@"su"];
    [c encodeInteger:self.ringKind forKey:@"ring"];
    [c encodeObject:self.roles forKey:@"roles"];
}

+ (NSString *)nameForRing:(NURingKind)k {
    switch (k) {
        case NURingIrreflexive: return @"ir";
        case NURingAsymmetric: return @"as";
        case NURingIntransitive: return @"it";
        case NURingAcyclic: return @"ac";
        case NURingSymmetric: return @"sy";
        case NURingAntisymmetric: return @"ans";
        case NURingTransitive: return @"tr";
        default: return @"";
    }
}

- (NSUInteger)arity { return self.roles.count; }

- (NSRect)frame {
    CGFloat n = MAX((CGFloat)self.roles.count, 1);
    return NSMakeRect(self.origin.x, self.origin.y, n * kRole, kRole);
}

- (NSRect)roleFrameAtIndex:(NSUInteger)i {
    return NSMakeRect(self.origin.x + (CGFloat)i * kRole, self.origin.y, kRole, kRole);
}

- (NSString *)verbalizationUsing:(id)diagram {
    NUDiagram *d = (NUDiagram *)diagram;
    NSMutableArray *names = [NSMutableArray array];
    for (NURole *r in self.roles) {
        NUObjectType *ot = [d objectTypeWithId:r.playerId];
        [names addObject:ot ? ot.name : @"?"];
    }
    NSString *pred = self.reading ?: @"";
    NSMutableString *s = [NSMutableString string];
    if ([pred rangeOfString:@"..."].location != NSNotFound) {
        NSArray *parts = [pred componentsSeparatedByString:@"..."];
        NSUInteger ni = 0;
        for (NSUInteger i = 0; i < parts.count; i++) {
            [s appendString:parts[i]];
            if (i + 1 < parts.count && ni < names.count)
                [s appendString:names[ni++]];
        }
    } else if (names.count == 1) {
        [s appendFormat:@"%@ %@", names[0], pred];
    } else if (names.count >= 2) {
        [s appendFormat:@"%@ %@ %@", names[0], pred, names[1]];
        for (NSUInteger i = 2; i < names.count; i++)
            [s appendFormat:@" %@", names[i]];
    } else {
        [s appendString:pred];
    }
    [s appendString:@"."];
    NSUInteger i = 0;
    for (NURole *r in self.roles) {
        NUObjectType *ot = [d objectTypeWithId:r.playerId];
        NSString *n = ot.name ?: @"this role";
        if (r.unique)
            [s appendFormat:@" Each %@ plays that role at most once.", n];
        if (r.mandatory)
            [s appendFormat:@" Each %@ plays that role at least once.", n];
        i++;
    }
    if (self.spanningUnique && self.roles.count > 1)
        [s appendString:@" Each combination of role-players occurs at most once."];
    for (NURole *r in self.roles) {
        if (![r hasFrequency]) continue;
        NUObjectType *ot = [d objectTypeWithId:r.playerId];
        [s appendFormat:@" Each %@ plays that role %@ time(s).",
         ot.name ?: @"object", [r frequencyLabel]];
    }
    if (self.ringKind != NURingNone)
        [s appendFormat:@" The predicate is %@.", [NUFactType nameForRing:self.ringKind]];
    return s;
}

@end

@implementation NUSubtype

- (instancetype)init {
    self = [super init];
    if (self) _identifier = NUMakeUUID();
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _identifier = [[c decodeObjectForKey:@"id"] copy] ?: NUMakeUUID();
        _subId = [[c decodeObjectForKey:@"sub"] copy];
        _superId = [[c decodeObjectForKey:@"sup"] copy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.identifier forKey:@"id"];
    [c encodeObject:self.subId forKey:@"sub"];
    [c encodeObject:self.superId forKey:@"sup"];
}

@end

@implementation NURoleRef
+ (instancetype)refToFact:(NSString *)factId role:(NSInteger)i {
    NURoleRef *r = [[NURoleRef alloc] init];
    r.factId = factId;
    r.roleIndex = i;
    return r;
}
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _factId = [[c decodeObjectForKey:@"f"] copy];
        _roleIndex = [c decodeIntegerForKey:@"i"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.factId forKey:@"f"];
    [c encodeInteger:self.roleIndex forKey:@"i"];
}
@end

@implementation NUConstraint
- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = NUMakeUUID();
        _roles = [NSMutableArray array];
        _splitIndex = 1;
        _badge = NSMakePoint(80, 80);
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _identifier = [[c decodeObjectForKey:@"id"] copy] ?: NUMakeUUID();
        _kind = [c decodeIntegerForKey:@"k"];
        _roles = [[c decodeObjectForKey:@"r"] mutableCopy] ?: [NSMutableArray array];
        _splitIndex = [c decodeIntegerForKey:@"sp"];
        _badge.x = [c decodeDoubleForKey:@"bx"];
        _badge.y = [c decodeDoubleForKey:@"by"];
        if (_splitIndex < 1) _splitIndex = 1;
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.identifier forKey:@"id"];
    [c encodeInteger:self.kind forKey:@"k"];
    [c encodeObject:self.roles forKey:@"r"];
    [c encodeInteger:self.splitIndex forKey:@"sp"];
    [c encodeDouble:self.badge.x forKey:@"bx"];
    [c encodeDouble:self.badge.y forKey:@"by"];
}
- (NSString *)markLabel {
    switch (self.kind) {
        case NUConstraintSubset: return @"SS";
        case NUConstraintEquality: return @"=";
        case NUConstraintExclusion: return @"X";
        default: return @"U";
    }
}
- (NSString *)verbalizationUsing:(id)diagram {
    NUDiagram *d = (NUDiagram *)diagram;
    NSMutableArray *names = [NSMutableArray array];
    for (NURoleRef *ref in self.roles) {
        NUFactType *ft = [d factTypeWithId:ref.factId];
        NSString *pn = @"?";
        if (ft && ref.roleIndex >= 0 && ref.roleIndex < (NSInteger)ft.roles.count) {
            NURole *role = ft.roles[ref.roleIndex];
            NUObjectType *ot = [d objectTypeWithId:role.playerId];
            pn = ot.name ?: @"?";
        }
        [names addObject:pn];
    }
    NSString *list = [names componentsJoinedByString:@", "];
    switch (self.kind) {
        case NUConstraintSubset: {
            NSInteger sp = MIN(self.splitIndex, (NSInteger)names.count);
            NSArray *left = [names subarrayWithRange:NSMakeRange(0, MAX(sp, 0))];
            NSArray *right = (sp < (NSInteger)names.count)
                ? [names subarrayWithRange:NSMakeRange(sp, names.count - sp)]
                : @[];
            return [NSString stringWithFormat:@"The population of (%@) is a subset of (%@).",
                    [left componentsJoinedByString:@", "],
                    [right componentsJoinedByString:@", "]];
        }
        case NUConstraintEquality:
            return [NSString stringWithFormat:@"The populations of %@ are equal.", list];
        case NUConstraintExclusion:
            return [NSString stringWithFormat:@"The populations of %@ are mutually exclusive.", list];
        default:
            return [NSString stringWithFormat:@"Each combination of %@ occurs at most once (external uniqueness).", list];
    }
}
@end

@implementation NUDiagram

- (instancetype)init {
    self = [super init];
    if (self) {
        _title = @"Untitled";
        _objectTypes = [NSMutableArray array];
        _factTypes = [NSMutableArray array];
        _subtypes = [NSMutableArray array];
        _constraints = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _title = [[c decodeObjectForKey:@"title"] copy] ?: @"Untitled";
        _objectTypes = [[c decodeObjectForKey:@"ot"] mutableCopy] ?: [NSMutableArray array];
        _factTypes = [[c decodeObjectForKey:@"ft"] mutableCopy] ?: [NSMutableArray array];
        _subtypes = [[c decodeObjectForKey:@"st"] mutableCopy] ?: [NSMutableArray array];
        _constraints = [[c decodeObjectForKey:@"cs"] mutableCopy] ?: [NSMutableArray array];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.title forKey:@"title"];
    [c encodeObject:self.objectTypes forKey:@"ot"];
    [c encodeObject:self.factTypes forKey:@"ft"];
    [c encodeObject:self.subtypes forKey:@"st"];
    [c encodeObject:self.constraints forKey:@"cs"];
}

- (NUFactType *)factTypeWithId:(NSString *)identifier {
    for (NUFactType *f in self.factTypes)
        if ([f.identifier isEqualToString:identifier]) return f;
    return nil;
}

- (NUObjectType *)objectTypeWithId:(NSString *)identifier {
    for (NUObjectType *o in self.objectTypes)
        if ([o.identifier isEqualToString:identifier]) return o;
    return nil;
}

- (NUObjectType *)addObjectTypeNamed:(NSString *)name kind:(NUObjectKind)kind {
    NUObjectType *o = [[NUObjectType alloc] init];
    o.name = name;
    o.kind = kind;
    NSUInteger n = self.objectTypes.count;
    o.origin = NSMakePoint(40 + (n % 4) * 180, 40 + (n / 4) * 90);
    if (kind == NUObjectValue) o.size = NSMakeSize(130, 50);
    [self.objectTypes addObject:o];
    return o;
}

- (void)removeObjectType:(NUObjectType *)ot {
    if (!ot) return;
    NSString *oid = ot.identifier;
    for (NUFactType *ft in self.factTypes)
        for (NURole *r in ft.roles)
            if ([r.playerId isEqualToString:oid]) r.playerId = @"";
    NSMutableArray *drop = [NSMutableArray array];
    for (NUSubtype *s in self.subtypes)
        if ([s.subId isEqualToString:oid] || [s.superId isEqualToString:oid])
            [drop addObject:s];
    [self.subtypes removeObjectsInArray:drop];
    [self.objectTypes removeObject:ot];
}

- (void)dropConstraintsTouchingFact:(NSString *)fid {
    NSMutableArray *drop = [NSMutableArray array];
    for (NUConstraint *c in self.constraints)
        for (NURoleRef *r in c.roles)
            if ([r.factId isEqualToString:fid]) { [drop addObject:c]; break; }
    [self.constraints removeObjectsInArray:drop];
}

- (NUFactType *)addFactWithPlayers:(NSArray<NUObjectType *> *)players
                           reading:(NSString *)reading {
    NUFactType *ft = [[NUFactType alloc] init];
    ft.reading = reading;
    CGFloat ax = 0, ay = 0;
    NSUInteger k = 0;
    for (NUObjectType *p in players) {
        NURole *r = [[NURole alloc] init];
        r.playerId = p.identifier;
        [ft.roles addObject:r];
        ax += NSMidX([p frame]);
        ay += NSMaxY([p frame]);
        k++;
    }
    if (k == 0)
        ft.origin = NSMakePoint(80 + self.factTypes.count * 20, 200);
    else
        ft.origin = NSMakePoint(ax / k - (CGFloat)k * 14.0, ay / k + 16);
    [self.factTypes addObject:ft];
    return ft;
}

- (void)removeFactType:(NUFactType *)ft {
    if (!ft) return;
    [self dropConstraintsTouchingFact:ft.identifier];
    [self.factTypes removeObject:ft];
}

- (NUConstraint *)addConstraint:(NUConstraintKind)kind
                          roles:(NSArray<NURoleRef *> *)roles
                          split:(NSInteger)split
                          badge:(NSPoint)badge {
    if (roles.count < 2) return nil;
    NUConstraint *c = [[NUConstraint alloc] init];
    c.kind = kind;
    c.roles = [roles mutableCopy];
    c.splitIndex = (split > 0) ? split : 1;
    c.badge = badge;
    [self.constraints addObject:c];
    return c;
}

- (void)removeConstraint:(NUConstraint *)c {
    if (c) [self.constraints removeObject:c];
}

- (NUSubtype *)addSubtypeFrom:(NUObjectType *)sub to:(NUObjectType *)sup {
    if (!sub || !sup || sub == sup) return nil;
    for (NUSubtype *s in self.subtypes)
        if ([s.subId isEqualToString:sub.identifier] &&
            [s.superId isEqualToString:sup.identifier]) return s;
    NUSubtype *s = [[NUSubtype alloc] init];
    s.subId = sub.identifier;
    s.superId = sup.identifier;
    [self.subtypes addObject:s];
    return s;
}

- (void)removeSubtype:(NUSubtype *)s {
    if (s) [self.subtypes removeObject:s];
}

- (NSData *)archivedData {
    return [NSKeyedArchiver archivedDataWithRootObject:self];
}

+ (instancetype)diagramWithData:(NSData *)data error:(NSError **)error {
    @try {
        id obj = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        if ([obj isKindOfClass:[NUDiagram class]]) return obj;
    } @catch (NSException *ex) {
        if (error)
            *error = [NSError errorWithDomain:@"NativeORM" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: ex.reason ?: @"bad file"}];
    }
    return nil;
}

- (NSString *)exportedVerbalization {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"* %@\n* Object-Role Model (ORM2).\n\n", self.title];
    [s appendString:@"Object types\n------------\n"];
    for (NUObjectType *o in self.objectTypes)
        [s appendFormat:@"%@\n", [o verbalization]];
    [s appendString:@"\nFact types\n----------\n"];
    for (NUFactType *ft in self.factTypes)
        [s appendFormat:@"%@\n", [ft verbalizationUsing:self]];
    if (self.subtypes.count) {
        [s appendString:@"\nSubtypes\n--------\n"];
        for (NUSubtype *st in self.subtypes) {
            NUObjectType *a = [self objectTypeWithId:st.subId];
            NUObjectType *b = [self objectTypeWithId:st.superId];
            [s appendFormat:@"%@ is a subtype of %@.\n", a.name, b.name];
        }
    }
    if (self.constraints.count) {
        [s appendString:@"\nConstraints\n-----------\n"];
        for (NUConstraint *c in self.constraints)
            [s appendFormat:@"%@\n", [c verbalizationUsing:self]];
    }
    return s;
}

+ (instancetype)miniNotesSeed {
    NUDiagram *d = [[NUDiagram alloc] init];
    d.title = @"MiniNotes — ORM2 conceptual schema";

    NUObjectType *(^ent)(NSString *, NSString *, CGFloat, CGFloat) =
    ^(NSString *name, NSString *ref, CGFloat x, CGFloat y) {
        NUObjectType *o = [[NUObjectType alloc] init];
        o.name = name; o.kind = NUObjectEntity; o.referenceMode = ref ?: @"";
        o.origin = NSMakePoint(x, y); o.size = NSMakeSize(150, 58);
        [d.objectTypes addObject:o];
        return o;
    };
    NUObjectType *(^val)(NSString *, NSString *, CGFloat, CGFloat) =
    ^(NSString *name, NSString *vc, CGFloat x, CGFloat y) {
        NUObjectType *o = [[NUObjectType alloc] init];
        o.name = name; o.kind = NUObjectValue; o.valueConstraint = vc ?: @"";
        o.origin = NSMakePoint(x, y); o.size = NSMakeSize(130, 50);
        [d.objectTypes addObject:o];
        return o;
    };

    NUObjectType *app  = ent(@"Application", @"",     40,  40);
    NUObjectType *nb   = ent(@"Notebook",    @"id",  280,  40);
    NUObjectType *note = ent(@"Note",        @"id",  560,  40);
    NUObjectType *win  = ent(@"Window",      @"",     40, 260);

    NUObjectType *title = val(@"Title",  @"",              820,  20);
    NUObjectType *body  = val(@"Body",   @"",              820, 110);
    NUObjectType *when  = val(@"Instant", @"",             820, 200);
    NUObjectType *selId = val(@"NoteId", @"{UUID string}", 280, 260);

    NUFactType *(^bin)(NUObjectType *, NSString *, NUObjectType *,
                       BOOL, BOOL, BOOL, BOOL, CGFloat, CGFloat) =
    ^(NUObjectType *a, NSString *rd, NUObjectType *b,
      BOOL u0, BOOL m0, BOOL u1, BOOL m1, CGFloat x, CGFloat y) {
        NUFactType *ft = [d addFactWithPlayers:@[a, b] reading:rd];
        ft.origin = NSMakePoint(x, y);
        NURole *r0 = ft.roles[0], *r1 = ft.roles[1];
        r0.unique = u0; r0.mandatory = m0;
        r1.unique = u1; r1.mandatory = m1;
        return ft;
    };

    NUFactType *editing = bin(app, @"is editing", nb, YES, NO, NO, NO, 180, 130);
    NUFactType *contains = bin(nb, @"contains", note, NO, NO, YES, YES, 430, 130);
    NUFactType *hasTitle = bin(note, @"has", title, YES, YES, NO, NO, 700, 70);
    bin(note, @"has", body, YES, YES, NO, NO, 700, 155);
    bin(note, @"was created at", when, YES, YES, NO, NO, 620, 250);
    bin(note, @"was modified at", when, YES, YES, NO, NO, 720, 300);
    NUFactType *displays = bin(win, @"displays", nb, YES, NO, NO, NO, 160, 220);
    bin(nb, @"has selected", selId, YES, NO, NO, NO, 360, 220);

    /* frequency: a notebook is shown in at most 4 windows */
    displays.roles[1].freqMin = 0;
    displays.roles[1].freqMax = 4;

    NUObjectType *tag = val(@"Tag", @"{1..32 chars}", 820, 360);
    NUFactType *tagged = [d addFactWithPlayers:@[note, tag] reading:@"is tagged with"];
    tagged.origin = NSMakePoint(640, 380);
    tagged.spanningUnique = YES;
    tagged.roles[0].freqMin = 0;
    tagged.roles[0].freqMax = 8;

    NUFactType *archived = [d addFactWithPlayers:@[note] reading:@"is archived"];
    archived.origin = NSMakePoint(560, 200);
    archived.roles[0].unique = YES;
    NUFactType *pinned = [d addFactWithPlayers:@[note] reading:@"is pinned"];
    pinned.origin = NSMakePoint(500, 200);
    pinned.roles[0].unique = YES;

    NUFactType *refs = [d addFactWithPlayers:@[note, note] reading:@"references"];
    refs.origin = NSMakePoint(480, 330);
    refs.spanningUnique = YES;
    refs.ringKind = NURingIrreflexive;

    [d addConstraint:NUConstraintExclusion
               roles:@[[NURoleRef refToFact:archived.identifier role:0],
                       [NURoleRef refToFact:pinned.identifier role:0]]
               split:1
               badge:NSMakePoint(530, 170)];

    [d addConstraint:NUConstraintExternalUnique
               roles:@[[NURoleRef refToFact:contains.identifier role:0],
                       [NURoleRef refToFact:hasTitle.identifier role:1]]
               split:1
               badge:NSMakePoint(560, 100)];

    [d addConstraint:NUConstraintSubset
               roles:@[[NURoleRef refToFact:displays.identifier role:1],
                       [NURoleRef refToFact:editing.identifier role:1]]
               split:1
               badge:NSMakePoint(220, 175)];

    return d;
}

@end
