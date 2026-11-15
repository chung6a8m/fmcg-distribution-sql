#!/usr/bin/env python3
"""Check the technology-neutral business contract. No application is executed.

Requires Python standard library only; this is documentation tooling, not product stack.
Never interprets synthetic/model validation as Product Verification or Go-Live.
"""
import datetime
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIZ = ROOT / "business"
ERRORS = []

def fail(message):
    ERRORS.append(message)

def check(condition, message):
    if not condition:
        fail(message)

def load(relative):
    path = ROOT / relative
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        fail(f"{relative}: {exc}")
        return {}

def ids_from_table(relative, pattern):
    text = (ROOT / relative).read_text(encoding="utf-8")
    return set(re.findall(pattern, text, flags=re.MULTILINE))

def require_range(values, stem, total):
    expected = {f"{stem}-{i:02d}" for i in range(1, total + 1)}
    check(values == expected,
          f"{stem} catalog mismatch: missing={sorted(expected - values)}, extra={sorted(values - expected)}")

# 1. Normative catalog and SOP completeness
rules = {"BR-" + x for x in ids_from_table(
    "business/business-rules.md", r"^\|\s*\*\*BR-(\d{2})\*\*\s*\|")}
policies = {"POL-" + x for x in ids_from_table(
    "business/policies.md", r"^\|\s*POL-(\d{2})\s*\|")}
approvals = {"AP-" + x for x in ids_from_table(
    "business/roles-and-approvals.md", r"^\|\s*AP-(\d{2})(?:\s|\|)")}
acceptance = {"AC-" + x for x in ids_from_table(
    "business/acceptance.md", r"^\|\s*\*\*AC-(\d{2})\*\*\s*\|")}
decision_text = (BIZ / "decisions.md").read_text(encoding="utf-8")
decisions = {"D-" + x for x in re.findall(r"^\|\s*D-(\d{2})\s*\|", decision_text, re.MULTILINE)}
padrs = {"PADR-" + x for x in re.findall(r"^\|\s*PADR-(\d{2})\s*\|", decision_text, re.MULTILINE)}
evqs = {"EVQ-" + x for x in re.findall(r"^\|\s*EVQ-(\d{2})\s*\|", decision_text, re.MULTILINE)}
sops = set()
for doc in (BIZ / "workflows").glob("*.md"):
    text = doc.read_text(encoding="utf-8")
    sops |= {"SOP-" + x for x in re.findall(r"^#{1,3}\s*SOP-(\d{2})\b", text, re.MULTILINE)}

for group, prefix, count in [
    (rules, "BR", 24), (policies, "POL", 24), (approvals, "AP", 10),
    (acceptance, "AC", 21), (decisions, "D", 15),
    (padrs, "PADR", 9), (evqs, "EVQ", 7), (sops, "SOP", 12)
]:
    require_range(group, prefix, count)

# 2. Local file links (Markdown) in the new repository, no historical repo required
for doc in [ROOT / "README.md", ROOT / "AGENTS.md", *BIZ.rglob("*.md")]:
    body = doc.read_text(encoding="utf-8")
    for url in re.findall(r"\]\(([^)]+)\)", body):
        target = url.split("#", 1)[0].strip()
        if not target or target.startswith(("https://", "http://", "mailto:", "#")):
            continue
        resolved = (doc.parent / target).resolve()
        check(resolved.is_relative_to(ROOT.resolve()) and resolved.exists(),
              f"Broken internal link: {doc.relative_to(ROOT)} -> {target}")

# 3. Machine-readable cases
data = load("business/reference-data/scenarios/business-cases.json")
cases = data.get("cases", [])
case_ids = [case.get("id") for case in cases]
check(data.get("metadata", {}).get("runtimeStatus") == "NOT_RUN",
      "Scenario runtimeStatus must remain NOT_RUN")
check(set(case_ids) == acceptance and len(case_ids) == len(set(case_ids)),
      "Scenario IDs must match AC-01..21 exactly once")
for case in cases:
    check(case.get("status") == "NOT_RUN" and case.get("evidenceKind") == "BUSINESS_SCENARIO_ONLY",
          f"{case.get('id')}: do not assert Product Verification from synthetic data")
    check(bool(case.get("given") and case.get("when") and case.get("then")),
          f"{case.get('id')}: missing Given/When/Then")
    check(bool(case.get("ruleRefs")) and set(case.get("ruleRefs", [])).issubset(rules),
          f"{case.get('id')}: missing or unknown BR")
    ref = case.get("oracleRef")
    if ref:
        path, _, key = ref.partition("#")
        obj = load("business/reference-data/" + path)
        check(key in obj, f"{case.get('id')}: oracle ref missing: {ref}")

seed = load("business/reference-data/master-data/seed.json")
check(seed.get("metadata", {}).get("status") == "SYNTHETIC", "Seed must remain SYNTHETIC")
tenant_ids = {x["tenantId"] for x in seed.get("tenants", [])}
customer_ids = {x["customerId"] for x in seed.get("customers", [])}
check(len(tenant_ids) >= 2, "Isolation sample needs two tenants")
for customer in seed.get("customers", []):
    check(customer["tenantId"] in tenant_ids, "Customer references missing tenant")
for outlet in seed.get("outlets", []):
    check(outlet["customerId"] in customer_ids and outlet["tenantId"] in tenant_ids,
          "Outlet references missing customer/tenant")
    customer = next(c for c in seed["customers"] if c["customerId"] == outlet["customerId"])
    check(customer["tenantId"] == outlet["tenantId"], "Cross-tenant outlet reference")
check(any(len(x["outletIds"]) == 0 for x in seed["customers"]), "No 0-Outlet Customer sample")
check(seed.get("taxRatesForRealSales") is None, "Synthetic VAT must never become real default")
for tenant in seed["tenants"]:
    check(tenant.get("defaultCreditPolicyStatus") == "UNSET"
          and tenant.get("creditLimit") is None
          and tenant.get("creditTermsDays") is None,
          "Credit UNSET must not be represented as APPROVED zero")

# 4. Frozen R010-S2 model oracle consistency
golden = load("business/reference-data/expected-results/golden-oracles.json")
check(set(golden) == {"AC-03", "AC-19", "AC-20", "AC-21"}, "Frozen oracle ID set changed")
for case in golden.values():
    check(case.get("status") == "MODEL_ONLY", "Frozen oracle must remain MODEL_ONLY")

mixed = golden.get("AC-03", {})
rows = [dict(zip(mixed.get("cols", []), row)) for row in mixed.get("steps", [])]
check(len(rows) == 7, "AC-03 expected seven independent snapshots")
for r in rows:
    check(r["mainQty"] + r["tripQty"] + r["soldQty"] == 100,
          f"AC-03 {r['step']} quantity conservation")
    check(r["mainCost"] + r["tripCost"] + r["cogs"] == 1000,
          f"AC-03 {r['step']} cost conservation")
    check(all(v >= 0 for k, v in r.items() if k != "step"),
          f"AC-03 {r['step']} negative balance")
if rows:
    final = rows[-1]
    for field, value in {"mainQty": 55, "tripQty": 0, "cogs": 450, "aHold": 15,
                         "arA": 375, "arB": 100, "custody": 0, "fund": 200}.items():
        check(final[field] == value, f"AC-03 final {field} mismatch")

pricing = golden.get("AC-19", {})
for mode in ("EXCLUSIVE", "INCLUSIVE"):
    lines = pricing.get(mode, [])
    totals = pricing.get("totals", {}).get(mode)
    check(len(lines) == 2 and len(totals or []) == 3, f"AC-19 {mode} shape")
    if len(lines) == 2 and totals and len(totals) == 3:
        check([sum(line[i] for line in lines) for i in (3, 4, 5)] == totals,
              f"AC-19 {mode} line/totals mismatch")
        check(all(line[3] + line[4] == line[5] for line in lines),
              f"AC-19 {mode} net+VAT != gross")
check(pricing.get("creditBeforeRefund", 0) - pricing.get("refundDisbursed", 0)
      == pricing.get("creditAfterRefund"), "AC-19 refund credit mismatch")
check(sum(x[0] for x in pricing.get("returnParts", [])) == 193333,
      "AC-19 return net remainder not preserved")
check(sum(x[1] for x in pricing.get("returnParts", [])) == 15467,
      "AC-19 return tax remainder not preserved")

advance = golden.get("AC-20", {})
for row in advance.get("steps", []):
    step, issued, expense, accepted, outstanding = row
    check(issued - expense - accepted == outstanding >= 0,
          f"AC-20 {step}: outstanding mismatch")
check([r[-1] for r in advance.get("steps", [])] == [500000, 200000, 200000, 100000, 0],
      "AC-20 steps mismatch")

receipts = golden.get("AC-21", {})
for r in receipts.get("steps", []):
    step, ar, credit, custody, fund, allocated = r
    check(ar + allocated == 140000 and credit + allocated == 60000,
          f"AC-21 {step}: receivable/credit mismatch")
    check(custody + fund == 60000, f"AC-21 {step}: cash custody conservation")
check(receipts.get("steps", [])[-1][1:] == [105000, 25000, 10000, 50000, 35000],
      "AC-21 ending balances mismatch")

# 5. Additional independent arithmetic oracles
additional = load("business/reference-data/expected-results/additional-oracles.json")
check(additional.get("metadata", {}).get("status") == "MODEL_ONLY",
      "Additional oracles must remain MODEL_ONLY")
cost = additional["AC-06"]
check(cost["firstRefund"] + cost["originalSecondRefund"] == cost["expectedOriginalSum"] == 6667,
      "AC-06 original cumulative cost mismatch")
check(cost["firstRefund"] + cost["firstRefundAdjustment"] + cost["finalSecondRefund"]
      == cost["expectedAdjustedSum"] == cost["sourceAdjustedCost"] == 6768,
      "AC-06 adjusted cumulative cost mismatch")
gift = additional["AC-07"]
threshold = gift["program"]["qualifiedPurchaseThreshold"]
for label, info in (("returned", gift["branchReturned"]), ("waived", gift["branchWaived"])):
    net = info["initialPurchases"] - info["purchaseReturnAccepted"] + info["subsequentPurchase"]
    held = info["initialGiftDelivered"] - info["giftReturnAccepted"]
    entitlement = net // threshold
    check(net == info["expectedNetPurchases"] and held == info["expectedGiftHeld"],
          f"AC-07 {label}: net/held mismatch")
    check(max(0, entitlement - held) == info["expectedGiftToDeliver"],
          f"AC-07 {label}: gift to deliver mismatch")
term = additional["AC-08"]
for row in term["deliveries"]:
    actual = datetime.date.fromisoformat(row["deliveryDate"]) + datetime.timedelta(days=term["confirmedTermsDays"])
    check(actual.isoformat() == row["expectedDueDate"], "AC-08 existing order due date mismatch")
new = term["newOrder"]
check((datetime.date.fromisoformat(new["deliveryDate"]) + datetime.timedelta(days=new["termsDays"])).isoformat()
      == new["expectedDueDate"], "AC-08 new order due date mismatch")
for row in additional["AC-09"]["cases"]:
    p, r, c = row["P"], row["verifiedReceiptApplied"], row["reservedCustomerCreditApplied"]
    exposure = p - r - c
    check(0 <= r + c <= p and exposure == row["expectedAR"],
          f"AC-09 {row['caseId']}: receivable mismatch")
    check(row["openingGrant"] - exposure == row["expectedGrantRemaining"] >= 0,
          f"AC-09 {row['caseId']}: grant mismatch")
    if "actualCashReceived" in row:
        check(row["actualCashReceived"] - r == row["expectedNewCustomerCredit"],
              "AC-09 overpayment credit mismatch")
    check(row["expectedCashCustodyDelta"] >= 0, "AC-09 negative cash custody")
negative = additional["AC-09"]["concurrencyNegative"]
check(negative["twoDistinctCommandsExposureEach"] * 2 > negative["openingGrant"]
      and negative["bothMayCommit"] is False, "AC-09 concurrency safety mismatch")

if ERRORS:
    for error in ERRORS:
        print("FAIL:", error)
    raise SystemExit(f"Business contract validation failed with {len(ERRORS)} finding(s)")
print(f"PASS: {len(rules)} BR, {len(policies)} POL, {len(approvals)} AP, "
      f"{len(decisions)} D, {len(padrs)} PADR, {len(evqs)} EVQ, "
      f"{len(sops)} SOP and {len(cases)} AC cases; "
      "all documented model-only arithmetic invariants checked.")
print("Scope: DOCUMENT/MODEL ONLY — not implementation, external integration or go-live verification.")
