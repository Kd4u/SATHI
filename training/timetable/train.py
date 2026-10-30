#!/usr/bin/env python3
"""Train the portable timetable cell-role classifier from reviewed feature rows.

Input: JSON list of {"fold": integer workbook group, "x": [11 floats], "y": 0|1}.
Keep labels/source spreadsheets private. Requires Python 3 and numpy.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

FEATURES = ["faculty", "knownCourse", "repeated", "tbd", "guest", "event", "time", "placeholder", "words", "numbered", "section"]
EVENT_TOKENS = ["QUIZ", "HOLIDAY", "EXAM", "MID TERM", "MID-TERM", "END TERM", "END-TERM", "BREAK", "VACATION", "INDEPENDENCE", "REPUBLIC", "DUSSEHRA", "DIWALI", "CHRISTMAS", "JAYANTI", "MILAD", "CHHATH", "CHATTH", "ELEGANTE", "NETRITVA", "TEDX", "CONCLAVE", "INTERNSHIP PRESENTATION", "NO CLASS", "ORIENTATION", "INDUCTION", "CONVOCATION"]

def train(x, y):
    # Mask faculty evidence in positive training rows to represent incomplete
    # faculty cells. Never augment held-out inputs or alter their labels.
    masked = x[y == 1].copy()
    masked[:, :2] = 0
    x = np.vstack([x, masked])
    y = np.r_[y, np.ones(len(masked), dtype=int)]
    a = np.column_stack([np.ones(len(x)), x])
    w = np.zeros(a.shape[1])
    balance = np.where(y == 1, len(y) / (2 * sum(y)), len(y) / (2 * sum(y == 0)))
    for _ in range(5000):
        pred = 1 / (1 + np.exp(-np.clip(a @ w, -30, 30)))
        gradient = a.T @ ((pred - y) * balance) / len(y) + np.r_[0, w[1:]] * 0.0003
        w -= 0.3 * gradient
    return w

def predict(x, w):
    return 1 / (1 + np.exp(-np.clip(np.column_stack([np.ones(len(x)), x]) @ w, -30, 30)))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--holdout-fold", type=int, default=4)
    args = parser.parse_args()
    data = args.examples.read_bytes()
    examples = json.loads(data)
    x = np.asarray([row["x"] for row in examples], dtype=float)
    y = np.asarray([row["y"] for row in examples], dtype=int)
    folds = np.asarray([row["fold"] for row in examples], dtype=int)
    if x.ndim != 2 or x.shape[1] != len(FEATURES) or not np.isfinite(x).all() or not set(y) <= {0, 1}:
        raise ValueError("Invalid reviewed feature data")
    if args.holdout_fold not in folds or len(set(folds)) < 2:
        raise ValueError("Reserve an entire workbook group for evaluation")
    results = []
    for fold in sorted(set(folds)):
        test = folds == fold
        if len(set(y[~test])) != 2:
            raise ValueError("Each training partition needs positive and negative examples")
        weights = train(x[~test], y[~test])
        truth = y[test]
        pred = predict(x[test], weights) >= .5
        tp = int(sum((pred == 1) & (truth == 1)))
        fp = int(sum((pred == 1) & (truth == 0)))
        fn = int(sum((pred == 0) & (truth == 1)))
        results.append(dict(fold=int(fold), examples=int(sum(test)), accuracy=float(np.mean(pred == truth)),
                            classPrecision=tp / max(1, tp + fp), classRecall=tp / max(1, tp + fn),
                            falsePositive=fp, falseNegative=fn))
    weights = train(x[folds != args.holdout_fold], y[folds != args.holdout_fold])
    model = dict(version=1, features=FEATURES, intercept=float(weights[0]), weights=weights[1:].tolist(),
                 threshold=.5, eventTokens=EVENT_TOKENS,
                 description="Binary timetable cell-role classifier; source positions and subject/section normalization remain deterministic.")
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "TimetableCellRole.json").write_text(json.dumps(model, indent=2))
    evaluation = dict(method="Leave-one-workbook-out; reviewed catalogue labels, not independently double-annotated.",
                      examplesSHA256=hashlib.sha256(data).hexdigest(), features=FEATURES,
                      trainingExamples=int(sum(folds != args.holdout_fold)),
                      augmentedPositiveTrainingRows=int(sum(y[folds != args.holdout_fold])),
                      heldOutFold=args.holdout_fold, heldOutExamples=int(sum(folds == args.holdout_fold)),
                      augmentation="Mask faculty and knownCourse on training-positive rows only.", folds=results)
    (args.output / "evaluation.json").write_text(json.dumps(evaluation, indent=2))
    print(json.dumps(evaluation, indent=2))

if __name__ == "__main__":
    main()
