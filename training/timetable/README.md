# Timetable cell-role model

This is a small **trained logistic classifier**, not a language model or chat assistant. It predicts whether a dated timetable entry is a class or background/event. Native Excel decoding, time parsing, subject-name normalization, section/programme extraction and source-cell accounting remain explicit. The model cannot invent omitted lectures or restore a truncated JSON export without the original workbook.

The shipped `apple/SWIFT/TimetableCellRole.json` contains fitted weights. Inference uses eleven numeric context features in native Swift, without a network request or additional runtime framework. The same format can support Android inference later; this change does not claim Android model integration.

## Preparation and training

1. Review a canonical course-name catalogue against the original Excel sheets. The catalogue is used to annotate training labels, not as a runtime subject dictionary. Review every entry that is neither a course nor a known event/placeholder.
2. Prepare feature rows with `prepare.py`. It stops on unreviewed labels and writes private source-cell provenance. Treat those files as private; they are not included in this repository.
3. Train with `train.py`. Entire workbook groups are held out. Positive training rows also receive a faculty-masked variant to represent incomplete instructor cells. Held-out examples are not augmented.
4. Compare the exported importer reports against the reviewed source cells, including per-subject/section counts. Cell-role accuracy alone does not prove correct extraction or complete saved data.

Development dependencies: Python 3, numpy and openpyxl. Example with your own reviewed input files:

```sh
python3 training/timetable/prepare.py --class-labels /private/course-labels.json --output /private/role-data term1.xlsx term2.xlsx term3.xlsx term4.xlsx term5.xlsx
python3 training/timetable/train.py /private/role-data/examples.json /private/trained --holdout-fold 4
```

Copy the reviewed model to the app only after evaluating it and running source-cell/count checks. Do not replace a production model merely because its training score is high.

## Measured results and limits

The dataset has 4,584 labelled dated-cell entries from five supplied workbook variations. The shipped model is trained on Terms I–IV: 3,996 original examples plus 2,700 faculty-masked positive examples. Term V is held out: 588 entries, consisting of 420 classes and 168 events. Its measured cell-role accuracy, class precision and class recall are 100% on that test.

The additional leave-one-workbook-out development runs have accuracy of 98.36–100%, class precision of 97.20–100% and class recall of 100%. The Term III fold produced 19 false positives for a `.` placeholder when that placeholder pattern was absent from training; inference therefore always rejects placeholders and time-only lines structurally. The reported model-only metrics retain those errors rather than hiding them.

These labels were reviewed by unique course/event catalogue and source context, not independently double-annotated by an institution. Five related workbooks are a small test set. These figures are **not a 95% guarantee for future formats**, nor a measurement of arbitrary subject-name understanding. Learned scores are not calibrated certainty. Review warnings remain necessary for missing faculty, unsupported layouts and inferred times.

`evaluation.json` records the split, metrics and SHA-256 of the private feature dataset. `source-cell-audit.json` records end-to-end counts verified against reviewed source cells: 768, 802, 659, 471 and 420 classes for Terms I–V respectively, with no missing/extra source-cell identities in those fixtures. Raw workbooks, labels containing source text, account exports and Firebase/signing configuration are excluded.
