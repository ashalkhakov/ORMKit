# Vendored third-party code

## DMTabBar

`DMTabBar/` is an Xcode-style icon tab bar by Daniele Margutti, 2012
(<http://www.danielemargutti.com>). It is **MIT licensed**: the licence's
text is `DMTabBar/LICENSE-DMTabBar.txt`, which the app carries among its
resources, as MIT asks of every copy. The copyright and licence notices in
each file are the author's, and are left as they stand.
MIT permits relicensing into an LGPL work, so ORMDesigner ships it under
ORMKit's LGPL 2.1 while those notices remain.

It is copied unchanged from RDLDesigner (`../RDLKit/RDLDesigner/ThirdParty`),
which took it from the XForms Designer and adapted it there:

* `DMTabBar.h` imports `<AppKit/AppKit.h>` rather than `<Cocoa/Cocoa.h>`.
  GNUstep has no Cocoa umbrella header, and CI rejects that import.
* `-setDefaults` derives the bar's gradient from `windowBackgroundColor`, so
  the bar follows a dark appearance.

The bar draws icons, not labels. ORMDesigner draws them with `ORMTabBadge`, a
port of RDLDesigner's `RDLTabBadge`.
