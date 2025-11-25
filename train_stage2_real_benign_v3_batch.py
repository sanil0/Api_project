#!/usr/bin/env python
"""
RETRAIN Stage 2 Model with REAL Benign Traffic (not synthetic)
Processing in batches due to large dataset size
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
MODEL_DIR = PROJECT_DIR / "models"

print("\n" + "=" * 100)
print("🔄 RETRAINING Stage 2 WITH REAL BENIGN TRAFFIC (Batch Processing)")
print("=" * 100)

# Load training data in batches
print("\n[STEP 1] Loading CICDDOS2019 training data with REAL benign (batch mode)...")

train_files = sorted(glob.glob("D:/DDoS_Project/CSV-01-12/01-12/*.csv"))

# Process first 3 files for tractability
X_train_list = []
y_train_list = []
total_rows = 0

for file in train_files[:3]:  # First 3 attack types to keep memory manageable
    print(f"  Processing {Path(file).name}...")
    df = pd.read_csv(file, nrows=150000)  # Limit rows per file
    
    # Extract numeric features
    numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()
    X = df[numeric_cols].fillna(0)
    X = np.nan_to_num(X.astype(float), nan=0.0, posinf=0.0, neginf=0.0)
    
    # Labels: 0 = Benign, 1 = Attack
    y = (df[' Label'] != 'BENIGN').astype(int)
    
    X_train_list.append(X)
    y_train_list.append(y)
    total_rows += len(df)
    
    print(f"    Loaded {len(df):,} rows. Benign: {(y==0).sum():,}, Attack: {(y==1).sum():,}")

# Combine all batches
X_train = np.vstack(X_train_list)
y_train = np.hstack(y_train_list)

print(f"\n✓ Total training samples: {len(X_train):,}")
print(f"  Benign: {(y_train == 0).sum():,} ({(y_train == 0).sum()/len(y_train)*100:.2f}%)")
print(f"  Attack: {(y_train == 1).sum():,} ({(y_train == 1).sum()/len(y_train)*100:.2f}%)")
print(f"✓ Features: {X_train.shape[1]}")

# Scale features
print(f"\n[STEP 2] Scaling features (MinMax [0, 1])...")
scaler = MinMaxScaler(feature_range=(0, 1))
X_train_scaled = scaler.fit_transform(X_train)
print(f"✓ Features scaled")

# Check imbalance before SMOTE
imbalance_ratio = (y_train == 1).sum() / (y_train == 0).sum()
print(f"\n[STEP 3] Class imbalance analysis:")
print(f"  Imbalance ratio: {imbalance_ratio:.2f}:1 (Attack:Benign)")

# Apply SMOTE with lower k_neighbors due to smaller minority class
print(f"\n[STEP 4] Applying SMOTE for class balancing...")
k_neighbors = min(5, (y_train == 0).sum() - 1)  # Ensure k < minority class size
smote = SMOTE(random_state=42, k_neighbors=k_neighbors)
X_train_smote, y_train_smote = smote.fit_resample(X_train_scaled, y_train)

print(f"✓ SMOTE applied!")
print(f"  Before: {len(X_train_scaled):,} samples ({(y_train == 0).sum():,} benign, {(y_train == 1).sum():,} attack)")
print(f"  After: {len(X_train_smote):,} samples")
print(f"  Benign: {(y_train_smote == 0).sum():,} ({(y_train_smote == 0).sum()/len(y_train_smote)*100:.2f}%)")
print(f"  Attack: {(y_train_smote == 1).sum():,} ({(y_train_smote == 1).sum()/len(y_train_smote)*100:.2f}%)")

# Train Random Forest
print(f"\n[STEP 5] Training Random Forest classifier...")
start_time = time.time()

model = RandomForestClassifier(
    n_estimators=100,
    max_depth=15,
    random_state=42,
    n_jobs=-1,
    verbose=0
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

print(f"  Accuracy: {train_acc*100:.2f}%")
print(f"  Precision: {train_prec*100:.2f}%")
print(f"  Recall: {train_rec*100:.2f}%")
print(f"  F1-Score: {train_f1:.4f}")

# Test on CICDDOS test data
print(f"\n[STEP 7] Loading CICDDOS2019 test data (batch mode)...")

test_files = sorted(glob.glob("D:/DDoS_Project/CSV-03-11/03-11/*.csv"))
X_test_list = []
y_test_list = []

for file in test_files:  # All test files
    print(f"  Processing {Path(file).name}...")
    df = pd.read_csv(file, nrows=100000)  # Limit rows per file
    
    X = df[numeric_cols].fillna(0)
    X = np.nan_to_num(X.astype(float), nan=0.0, posinf=0.0, neginf=0.0)
    y = (df[' Label'] != 'BENIGN').astype(int)
    
    X_test_list.append(X)
    y_test_list.append(y)
    print(f"    Loaded {len(df):,} rows. Benign: {(y==0).sum():,}, Attack: {(y==1).sum():,}")

X_test = np.vstack(X_test_list)
y_test = np.hstack(y_test_list)

print(f"\n✓ Total test samples: {len(X_test):,}")
print(f"  Benign: {(y_test == 0).sum():,} ({(y_test == 0).sum()/len(y_test)*100:.2f}%)")
print(f"  Attack: {(y_test == 1).sum():,} ({(y_test == 1).sum()/len(y_test)*100:.2f}%)")

# Scale test data
X_test_scaled = scaler.transform(X_test)

# Test predictions
print(f"\n[STEP 8] Making predictions on test data...")
y_pred_test = model.predict(X_test_scaled)

test_acc = accuracy_score(y_test, y_pred_test)
test_prec = precision_score(y_test, y_pred_test)
test_rec = recall_score(y_test, y_pred_test)
test_f1 = f1_score(y_test, y_pred_test)

print(f"  Accuracy: {test_acc*100:.2f}%")
print(f"  Precision: {test_prec*100:.2f}%")
print(f"  Recall: {test_rec*100:.2f}%")
print(f"  F1-Score: {test_f1:.4f}")

# Confusion Matrix
cm_test = confusion_matrix(y_test, y_pred_test)
print(f"\n  Confusion Matrix (Test Data):")
print(f"    True Negatives: {cm_test[0,0]:,}")
print(f"    False Positives: {cm_test[0,1]:,}")
print(f"    False Negatives: {cm_test[1,0]:,}")
print(f"    True Positives: {cm_test[1,1]:,}")

# False Positive Rate & False Negative Rate
fpr = cm_test[0,1] / (cm_test[0,0] + cm_test[0,1]) if (cm_test[0,0] + cm_test[0,1]) > 0 else 0
fnr = cm_test[1,0] / (cm_test[1,0] + cm_test[1,1]) if (cm_test[1,0] + cm_test[1,1]) > 0 else 0

print(f"\n  False Positive Rate (FPR): {fpr*100:.4f}%")
print(f"  False Negative Rate (FNR): {fnr*100:.4f}%")

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
    'model_version': 'v3_real_benign',
    'note': 'Trained with REAL benign samples from CICDDOS2019 (not synthetic)',
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
        'true_negatives': int(cm_test[0,0]),
        'false_positives': int(cm_test[0,1]),
        'false_negatives': int(cm_test[1,0]),
        'true_positives': int(cm_test[1,1])
    },
    'class_distribution': {
        'train_benign': int((y_train == 0).sum()),
        'train_attack': int((y_train == 1).sum()),
        'test_benign': int((y_test == 0).sum()),
        'test_attack': int((y_test == 1).sum())
    },
    'comparison_with_v2_synthetic': {
        'v2_accuracy': 1.0,
        'v2_benign_type': 'synthetic (uniform 0-0.1)',
        'v3_accuracy': float(test_acc),
        'v3_benign_type': 'REAL network patterns',
        'note': 'v3 is more realistic due to real benign samples'
    }
}

with open(MODEL_DIR / "hybrid_stage2_metrics_v3_real_benign.json", 'w') as f:
    json.dump(metrics, f, indent=2)

print(f"✓ Model saved: hybrid_stage2_model_v3_real_benign.pkl")
print(f"✓ Scaler saved: hybrid_stage2_scaler_v3_real_benign.pkl")
print(f"✓ Metrics saved: hybrid_stage2_metrics_v3_real_benign.json")

print("\n" + "=" * 100)
print("📊 MODEL COMPARISON")
print("=" * 100)

print(f"\n  VERSION 2 (Synthetic Benign):")
print(f"    Test Accuracy: 100.00%")
print(f"    Benign source: Synthetic (uniform random 0-0.1)")
print(f"    FPR: 0.00% (too good)")
print(f"    → Likely overfitted due to synthetic benign being too simple")

print(f"\n  VERSION 3 (Real Benign) - NEW:")
print(f"    Test Accuracy: {test_acc*100:.2f}%")
print(f"    Benign source: Real CICDDOS2019 network patterns")
print(f"    False Positive Rate: {fpr*100:.4f}% ← Critical metric")
print(f"    False Negative Rate: {fnr*100:.4f}% ← Critical metric")
print(f"    → More realistic and production-ready")

print(f"\n  KEY INSIGHT:")
print(f"    The 100% accuracy in v2 was because:")
print(f"    ✅ Synthetic benign = uniform 0-0.1 (extremely simple)")
print(f"    ❌ Real benign = diverse network patterns")
print(f"    → Model needs to work harder on real data")

print("\n" + "=" * 100 + "\n")
