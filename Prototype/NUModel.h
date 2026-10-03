#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NUObjectKind) {
    NUObjectEntity = 0,
    NUObjectValue
};

typedef NS_ENUM(NSInteger, NURingKind) {
    NURingNone = 0,
    NURingIrreflexive,      /* ir */
    NURingAsymmetric,       /* as */
    NURingIntransitive,     /* it */
    NURingAcyclic,          /* ac */
    NURingSymmetric,        /* sy */
    NURingAntisymmetric,    /* ans */
    NURingTransitive        /* tr */
};

typedef NS_ENUM(NSInteger, NUConstraintKind) {
    NUConstraintExternalUnique = 0, /* U circle */
    NUConstraintSubset,             /* ⊆  roles[0..split) ⊆ roles[split..] */
    NUConstraintEquality,           /* = */
    NUConstraintExclusion           /* ⊗ */
};

@interface NUObjectType : NSObject <NSCoding, NSCopying>
@property (copy) NSString *identifier;
@property (copy) NSString *name;
@property (assign) NUObjectKind kind;
@property (copy) NSString *referenceMode;
@property (copy) NSString *valueConstraint;
@property (assign) BOOL independent;
@property (assign) NSPoint origin;
@property (assign) NSSize size;
- (NSRect)frame;
- (NSString *)displayName;
- (NSString *)verbalization;
@end

@interface NURole : NSObject <NSCoding>
@property (copy) NSString *playerId;
@property (assign) BOOL mandatory;
@property (assign) BOOL unique;
@property (assign) NSInteger freqMin; /* 0 = no frequency constraint */
@property (assign) NSInteger freqMax; /* 0 = none, -1 = open upper bound */
- (BOOL)hasFrequency;
- (NSString *)frequencyLabel;
@end

@interface NUFactType : NSObject <NSCoding>
@property (copy) NSString *identifier;
@property (copy) NSString *reading;
@property (assign) NSPoint origin;
@property (assign) BOOL spanningUnique;
@property (assign) NURingKind ringKind;
@property (strong) NSMutableArray<NURole *> *roles;
- (NSUInteger)arity;
- (NSRect)frame;
- (NSRect)roleFrameAtIndex:(NSUInteger)i;
- (NSString *)verbalizationUsing:(id)diagram;
+ (NSString *)nameForRing:(NURingKind)k;
@end

@interface NUSubtype : NSObject <NSCoding>
@property (copy) NSString *identifier;
@property (copy) NSString *subId;
@property (copy) NSString *superId;
@end

@interface NURoleRef : NSObject <NSCoding>
@property (copy) NSString *factId;
@property (assign) NSInteger roleIndex;
+ (instancetype)refToFact:(NSString *)factId role:(NSInteger)i;
@end

@interface NUConstraint : NSObject <NSCoding>
@property (copy) NSString *identifier;
@property (assign) NUConstraintKind kind;
@property (strong) NSMutableArray<NURoleRef *> *roles;
@property (assign) NSInteger splitIndex; /* subset: left sequence length */
@property (assign) NSPoint badge;        /* centre of the constraint mark */
- (NSString *)markLabel;
- (NSString *)verbalizationUsing:(id)diagram;
@end

@interface NUDiagram : NSObject <NSCoding>
@property (copy) NSString *title;
@property (strong) NSMutableArray<NUObjectType *> *objectTypes;
@property (strong) NSMutableArray<NUFactType *> *factTypes;
@property (strong) NSMutableArray<NUSubtype *> *subtypes;
@property (strong) NSMutableArray<NUConstraint *> *constraints;
- (NUObjectType *)objectTypeWithId:(NSString *)identifier;
- (NUFactType *)factTypeWithId:(NSString *)identifier;
- (NUObjectType *)addObjectTypeNamed:(NSString *)name kind:(NUObjectKind)kind;
- (void)removeObjectType:(NUObjectType *)ot;
- (NUFactType *)addFactWithPlayers:(NSArray<NUObjectType *> *)players
                           reading:(NSString *)reading;
- (void)removeFactType:(NUFactType *)ft;
- (NUSubtype *)addSubtypeFrom:(NUObjectType *)sub to:(NUObjectType *)sup;
- (void)removeSubtype:(NUSubtype *)s;
- (NUConstraint *)addConstraint:(NUConstraintKind)kind
                          roles:(NSArray<NURoleRef *> *)roles
                          split:(NSInteger)split
                          badge:(NSPoint)badge;
- (void)removeConstraint:(NUConstraint *)c;
+ (instancetype)miniNotesSeed;
- (NSData *)archivedData;
+ (instancetype)diagramWithData:(NSData *)data error:(NSError **)error;
- (NSString *)exportedVerbalization;
@end
