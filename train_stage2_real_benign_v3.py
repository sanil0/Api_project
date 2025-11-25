#!/usr/bin/env python
"""
RETRAIN Stage 2 Model with REAL Benign Traffic (not synthetic)
Using actual benign samples from CICDDOS2019 dataset
"""

import pandas as pd
import numpy as np
import pickle
import json
from pathlib import Path
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import MinMaxScaler
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, confusion_matrix
from imblearn.over_sampling import SMOTE
import glob
import time

# === CONFIGURATION ===
PROJECT_DIR = Path(__file__).parent
DATA_DIR = PROJECT_DIR / "data"
MODEL_DIR = PROJECT_DIR / "models"

print("\n" + "=" * 100)
print("🔄 RETRAINING Stage 2 WITH REAL BENIGN TRAFFIC (NOT SYNTHETIC)")
print("=" * 100)

# Load training data with REAL benign samples
print("\n[STEP 1] Loading CICDDOS2019 training data with REAL benign...")

train_files = sorted(glob.glob("D:/DDoS_Project/CSV-01-12/01-12/*.csv"))
train_dfs = []

for file in train_files:
    print(f"  Loading {Path(file).name}...")
    df = pd.read_csv(file)
    train_dfs.append(df)

df_train = pd.concat(train_dfs, ignore_index=True)
print(f"\n✓ Total training samples: {len(df_train):,}")

# Check label distribution
print(f"\nLabel distribution BEFORE processing:")
label_counts = df_train[' Label'].value_counts()
for label, count in label_counts.items():
    print(f"  {label}: {count:,} ({count/len(df_train)*100:.2f}%)")

# Extract features and labels
numeric_cols = df_train.select_dtypes(include=[np.number]).columns.tolist()
X_train = df_train[numeric_cols].fillna(0)
X_train = np.nan_to_num(X_train.astype(float), nan=0.0, posinf=0.0, neginf=0.0)

# Labels: 0 = Benign, 1 = Attack
y_train = (df_train[' Label'] != 'BENIGN').astype(int)

print(f"\n✓ Features extracted: {X_train.shape[1]} features")
print(f"✓ Training samples: {len(y_train):,}")
print(f"  Benign: {(y_train == 0).sum():,} ({(y_train == 0).sum()/len(y_train)*100:.2f}%)")
print(f"  Attack: {(y_train == 1).sum():,} ({(y_train == 1).sum()/len(y_train)*100:.2f}%)")

# Scale features
print(f"\n[STEP 2] Scaling features (MinMax [0, 1])...")
scaler = MinMaxScaler(feature_range=(0, 1))
X_train_scaled = scaler.fit_transform(pd.DataFrame(X_train))
print(f"✓ Features scaled")

# Check imbalance before SMOTE
print(f"\n[STEP 3] Checking class imbalance...")
imbalance_ratio = (y_train == 1).sum() / (y_train == 0).sum()
print(f"  Imbalance ratio: {imbalance_ratio:.2f}:1 (Attack:Benign)")
print(f"  Benign:Attack ratio: 1:{imbalance_ratio:.2f}")

# Apply SMOTE
print(f"\n[STEP 4] Applying SMOTE for class balancing...")
smote = SMOTE(random_state=42, k_neighbors=5)
X_train_smote, y_train_smote = smote.fit_resample(X_train_scaled, y_train)

print(f"✓ SMOTE applied!")
print(f"  Before SMOTE: {len(X_train_scaled):,} samples ({(y_train == 0).sum():,} benign, {(y_train == 1).sum():,} attack)")
print(f"  After SMOTE: {len(X_train_smote):,} samples")
print(f"  New distribution:")
print(f"    Benign: {(y_train_smote == 0).sum():,} ({(y_train_smote == 0).sum()/len(y_train_smote)*100:.2f}%)")
print(f"    Attack: {(y_train_smote == 1).sum():,} ({(y_train_smote == 1).sum()/len(y_train_smote)*100:.2f}%)")

# Train Random Forest
print(f"\n[STEP 5] Training Random Forest classifier...")
start_time = time.time()

model = RandomForestClassifier(
    n_estimators=100,
    max_depth=15,
    random_state=42,
    n_jobs=-1,
    verbose=1
)

model.fit(X_train_smote, y_train_smote)
train_time = time.time() - start_time

print(f"✓ Training completed in {train_time:.2f} seconds")

# Evaluate on training data
print(f"\n[STEP 6] Evaluating on training data...")
y_pred_train = model.predict(X_train_scaled)

train_acc = accuracy_score(y_train, y_pred_train)
train_prec = precision_score(y_train, y_pred_train)
train_rec = recall_score(y_train, y_pred_train)
train_f1 = f1_score(y_train, y_pred_train)

print(f"  Training Accuracy: {train_acc*100:.2f}%")
print(f"  Training Precision: {train_prec*100:.2f}%")
print(f"  Training Recall: {train_rec*100:.2f}%")
print(f"  Training F1-Score: {train_f1:.4f}")

# Test on CICDDOS test data (with real benign)
print(f"\n[STEP 7] Loading CICDDOS2019 test data...")
test_files = sorted(glob.glob("D:/DDoS_Project/CSV-03-11/03-11/*.csv"))
test_dfs = []

for file in test_files:
    print(f"  Loading {Path(file).name}...")
    df = pd.read_csv(file)
    test_dfs.append(df)

df_test = pd.concat(test_dfs, ignore_index=True)
print(f"✓ Total test samples: {len(df_test):,}")

# Check test label distribution
print(f"\nLabel distribution in test data:")
test_label_counts = df_test[' Label'].value_counts()
for label, count in test_label_counts.items():
    print(f"  {label}: {count:,} ({count/len(df_test)*100:.2f}%)")

# Extract test features
X_test = df_test[numeric_cols].fillna(0)
X_test = np.nan_to_num(X_test.astype(float), nan=0.0, posinf=0.0, neginf=0.0)
y_test = (df_test[' Label'] != 'BENIGN').astype(int)

# Scale test data
X_test_scaled = scaler.transform(pd.DataFrame(X_test))

# Test predictions
print(f"\n[STEP 8] Making predictions on test data...")
y_pred_test = model.predict(X_test_scaled)

test_acc = accuracy_score(y_test, y_pred_test)
test_prec = precision_score(y_test, y_pred_test)
test_rec = recall_score(y_test, y_pred_test)
test_f1 = f1_score(y_test, y_pred_test)

print(f"  Test Accuracy: {test_acc*100:.2f}%")
print(f"  Test Precision: {test_prec*100:.2f}%")
print(f"  Test Recall: {test_rec*100:.2f}%")
print(f"  Test F1-Score: {test_f1:.4f}")

# Confusion Matrix
cm_test = confusion_matrix(y_test, y_pred_test)
print(f"\n  Confusion Matrix (Test Data):")
print(f"    TN: {cm_test[0,0]:,} | FP: {cm_test[0,1]:,}")
print(f"    FN: {cm_test[1,0]:,} | TP: {cm_test[1,1]:,}")

# False Positive Rate & False Negative Rate
fpr = cm_test[0,1] / (cm_test[0,0] + cm_test[0,1]) if (cm_test[0,0] + cm_test[0,1]) > 0 else 0
fnr = cm_test[1,0] / (cm_test[1,0] + cm_test[1,1]) if (cm_test[1,0] + cm_test[1,1]) > 0 else 0

print(f"\n  False Positive Rate (FPR): {fpr*100:.2f}%")
print(f"  False Negative Rate (FNR): {fnr*100:.2f}%")

# Save model and results
print(f"\n[STEP 9] Saving model and results...")

# Save model
with open(MODEL_DIR / "hybrid_stage2_model_v3_real_benign.pkl", 'wb') as f:
    pickle.dump(model, f)

# Save scaler
with open(MODEL_DIR / "hybrid_stage2_scaler_v3_real_benign.pkl", 'wb') as f:
    pickle.dump(scaler, f)

# Save metrics
metrics = {
    'training_time_seconds': train_time,
    'train_samples': len(X_train),
    'test_samples': len(X_test),
    'smote_samples': len(X_train_smote),
    'features': X_train.shape[1],
    'training': {
        'accuracy': float(train_acc),
        'precision': float(train_prec),
        'recall': float(train_rec),
        'f1_score': float(train_f1)
    },
    'test': {
        'accuracy': float(test_acc),
        'precision': float(test_prec),
        'recall': float(test_rec),
        'f1_score': float(test_f1),
        'false_positive_rate': float(fpr),
        'false_negative_rate': float(fnr),
        'tn': int(cm_test[0,0]),
        'fp': int(cm_test[0,1]),
        'fn': int(cm_test[1,0]),
        'tp': int(cm_test[1,1])
    },
    'class_distribution': {
        'train_benign': int((y_train == 0).sum()),
        'train_attack': int((y_train == 1).sum()),
        'test_benign': int((y_test == 0).sum()),
        'test_attack': int((y_test == 1).sum())
    }
}

with open(MODEL_DIR / "hybrid_stage2_metrics_v3_real_benign.json", 'w') as f:
    json.dump(metrics, f, indent=2)

print(f"✓ Model saved: hybrid_stage2_model_v3_real_benign.pkl")
print(f"✓ Scaler saved: hybrid_stage2_scaler_v3_real_benign.pkl")
print(f"✓ Metrics saved: hybrid_stage2_metrics_v3_real_benign.json")

print("\n" + "=" * 100)
print("🎯 RETRAINING COMPLETE - COMPARISON")
print("=" * 100)

print(f"\nMODEL VERSION COMPARISON:")
print(f"\n  v2 (Synthetic Benign):")
print(f"    Test Accuracy: 100.00%")
print(f"    Benign samples: 110,000 (synthetic, uniform 0-0.1)")
print(f"    → TOO GOOD TO BE TRUE (synthetic is too easy)")

print(f"\n  v3 (Real Benign):")
print(f"    Test Accuracy: {test_acc*100:.2f}%")
print(f"    Benign samples: ~{(y_test == 0).sum():,} (real network patterns)")
print(f"    False Positive Rate: {fpr*100:.2f}% ← CRITICAL for real networks")
print(f"    False Negative Rate: {fnr*100:.2f}% ← CRITICAL for security")
print(f"    → MORE REALISTIC evaluation")

print("\n" + "=" * 100 + "\n")
