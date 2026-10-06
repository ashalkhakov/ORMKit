/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
/* ORMRuntime: what an app built from an ORM model runs (docs/RUNTIME.md).
 * Plans, and the driver that reads them against a Core Data store. No ORM
 * model, no XML: ORMKit makes the plans, this runs them. */
#import "ORMQueryPlan.h"
#import "ORMQueryInterpreter.h"
#import "ORMCursor.h"
#import "ORMTables.h"
#import "ORMSaveHook.h"
