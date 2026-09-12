# PII surfaces checklist (direct disclosure)

Where directly-identifying information hides in a dataset/package. Walk all four
groups; a value-only scan sees only A1.

## A. Cell contents
- **A1 String values** — names, address, phone, email, national ID, free text,
  "other, specify". (visible)
- **A2 String residual/tail bytes** — the bytes stored after a fixed-width
  string's `\0` terminator; invisible to normal reads but written to disk and can
  hold fragments of prior values. Detect with the tail scanner.
- **A3 PII-bearing numerics** — national ID / SSN / phone / account numbers held
  as numbers; **GPS latitude/longitude**; **exact dates** (DOB, birth, admission,
  interview); age-in-days. Direct identifiers stored numerically, not analysis
  variables. Needs human judgment.

## B. Labels & metadata carried inside the file
- **B1 Value labels** — a numeric code (village, enumerator, respondent) whose
  *labels* are real names/places. Ships in the file; easy to miss. (dump all)
- **B2 Variable labels** — free-text labels containing a name/note/person.
- **B3 Variable names** — PII encoded in the name itself (e.g. a column per named
  person in a wide file).
- **B4 Dataset label, notes, characteristics** — free-text `notes`/`char`/dataset
  label often contain names, comments, or **embedded file paths that leak a
  username** (`C:\Users\jsmith\...`), original filenames, or settings that name an
  id variable.

## C. Other files in the package
- **C1 Non-primary data files** — CSV/Excel/JSON/txt: apply A and B.
- **C2 Documents & images** — PDFs/scans (consent forms), image EXIF/GPS, author
  metadata.
- **C3 Logs / temp / backup files** that echo raw data; **crosswalk/linking/key
  files** that must never ship at all.
- **C4 File paths in code** — usernames and machine paths inside the scripts.

## D. Structural 
- **D1 Row/sort order inherited from a removed identifier** — data still ordered
  by a deleted name column leaks that ordering.
- **D2 Direct unique identifiers (numeric or string) that could be linked to another source** — data
could be merged with another data source of the same individuals where pii may be held. 

Out of scope here: statistical / combination-based re-identification (k-anonymity,
l-diversity). This checklist is direct disclosure only.

## Notes from practice
- **B4 at scale.** Survey packages can carry both user-written narrative notes copied
  into data files and
  machine-generated characteristics from `reshape`/`xi`/
  `tsset` (`ReS_*`, `__xi__*`, `_TS*`). Count the two kinds separately; check
  whether any do-file reads notes/characteristics — usually none does, so they
  can be removed without touching code.
- **B1 false hits.** A direct-term search on value labels also catches innocent
  labels (for example "Pre-**Cast**ed", "**Name** Change", "**Birth** certificate");
  list them, let the reviewer dismiss.
- **A1 noise sources.** Interview times (`hh:mm`), counts, amounts
  and answer codes are numbers in disguise; the classifier routes them to `other`.
