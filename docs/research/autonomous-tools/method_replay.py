"""Synthetic replay only; no LLM, live retrieval, or empirical paper result.
Run: python3 method_replay.py --out PATH
All latent labels are held separately from the policy input.
"""
import argparse
import csv
import hashlib
import json
import platform
import random
import re
import statistics
import time
from collections import defaultdict
from difflib import SequenceMatcher
from pathlib import Path

SEED = 271828
METHODS = ['majority', 'url', 'text', 'group', 'ordinary', 'novelty', 'group_ordinary', 'group_novelty', 'group_gated', 'oracle']
REGIMES = ['clean', 'missing', 'split', 'merge']

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()

def generate(n=600):
    rng = random.Random(SEED)
    public, private = [], {}
    for i in range(n):
        cid = 'case-%04d' % i
        truth = rng.choice([-1, 1])
        records, roots = [], {}
        root_specs = []
        for r in range(7):
            rid = '%s-root-%d' % (cid, r)
            sign = truth if rng.random() < .72 else -truth
            phrase = rng.randrange(1000)
            root_specs.append((rid, sign, phrase))
        # Multiplicity is independent of correctness. Draw 8 initial results
        # with skewed weights, without exposing latent correctness to policies.
        weights = [rng.expovariate(1) for _ in range(4)]
        initial_roots = rng.choices(range(4), weights=weights, k=8)
        for j, r in enumerate(initial_roots + [rng.randrange(7) for _ in range(5)]):
            rid, sign, phrase = root_specs[r]
            eid = '%s-e%d' % (cid, j)
            variant = rng.randrange(3)
            text = 'Statement %s answer %s phrasing %04d version %d' % (cid, 'YES' if sign == 1 else 'NO', phrase, variant)
            records.append(dict(id=eid, url='https://mirror-%d.invalid/%s/%d' % (j % 3, cid, j), text=text, vote=sign, origin=rid))
            roots[eid] = rid
        # Root-disjoint development/test case IDs; source roots are case-scoped.
        public.append(dict(id=cid, split='dev' if i < 200 else 'test', initial=records[:8], candidates=records[8:]))
        private[cid] = dict(truth=truth, roots=roots)
    return public, private

def corrupt(cases, regime):
    rng = random.Random(SEED + REGIMES.index(regime) * 100)
    result = json.loads(json.dumps(cases))
    for case in result:
        for e in case['initial'] + case['candidates']:
            if regime == 'missing' and rng.random() < .6:
                e['origin'] = None
            elif regime == 'split' and rng.random() < .6:
                e['origin'] = e['id'] + '-unverified-origin'
            elif regime == 'merge' and rng.random() < .6:
                e['origin'] = case['id'] + '-shared-wrong-origin'
    return result

def normalize(text):
    return re.sub(r'\s+', ' ', text.lower()).strip()

def keys_for(records, mode):
    keys = []
    representatives = []
    for e in records:
        if mode == 'raw':
            key = e['id']
        elif mode == 'url':
            key = e['url']
        elif mode == 'group':
            key = ('origin:' + e['origin']) if e.get('origin') else ('text:' + normalize(e['text']))
        elif mode == 'text':
            text = normalize(e['text'])
            match = next((j for j, t in enumerate(representatives) if SequenceMatcher(None, text, t).ratio() >= .94), None)
            if match is None:
                match = len(representatives)
                representatives.append(text)
            key = str(match)
        else:
            raise ValueError(mode)
        keys.append(key)
    return keys

def aggregate(records, mode):
    groups = defaultdict(list)
    for e, key in zip(records, keys_for(records, mode)):
        groups[key].append(e['vote'])
    score = statistics.mean(statistics.mean(v) for v in groups.values())
    return (1 if score > 0 else -1 if score < 0 else 0), abs(score)

def choose(case, method):
    # The same five candidate metadata entries are available to every method.
    # Policy never sees their votes/text before choosing, only id/url/origin.
    initial = case['initial']
    meta = [{k: e[k] for k in ('id', 'url', 'origin')} for e in case['candidates']]
    seen = {e['origin'] for e in initial if e.get('origin')}
    novel = next((j for j, m in enumerate(meta) if m.get('origin') and m['origin'] not in seen), 0)
    gated = method == 'group_gated'
    conflict = len({e['vote'] for e in initial}) > 1
    query = method in ('ordinary', 'novelty', 'group_ordinary', 'group_novelty') or (gated and conflict)
    selected = novel if method in ('novelty', 'group_novelty', 'group_gated') else 0
    records = initial + ([case['candidates'][selected]] if query else [])
    mode = 'group' if method.startswith('group') else 'url' if method == 'url' else 'text' if method == 'text' else 'raw'
    pred, confidence = aggregate(records, mode)
    return dict(id=case['id'], split=case['split'], pred=pred, confidence=confidence, calls=int(query), records=len(records), selected=selected if query else None)

def calibrate(rows, labels):
    # Development only. Choose greatest coverage with <=10% observed error,
    # requiring >=30 answers. This is not a statistical risk guarantee.
    thresholds = sorted({r['confidence'] for r in rows if r['pred']})
    feasible = []
    for t in thresholds:
        answered = [r for r in rows if r['pred'] and r['confidence'] >= t]
        errors = sum(r['pred'] != labels[r['id']]['truth'] for r in answered)
        if len(answered) >= 30 and errors / len(answered) <= .1:
            feasible.append((len(answered), -t, t))
    return max(feasible)[2] if feasible else 1.000001

def metrics(rows, labels, threshold=0):
    accepted = [r for r in rows if r['pred'] and r['confidence'] >= threshold]
    wrong = sum(r['pred'] != labels[r['id']]['truth'] for r in accepted)
    return dict(n=len(rows), answered=len(accepted), wrong=wrong,
                coverage=len(accepted)/len(rows), wrong_per_question=wrong/len(rows),
                selective_error=wrong/len(accepted) if accepted else None,
                mean_calls=statistics.mean(r['calls'] for r in rows),
                mean_records=statistics.mean(r['records'] for r in rows))

def matched(rows, labels, fraction=.8):
    # Label-blind fixed-coverage diagnostic. Zero-score ties get a deterministic
    # random decision from case ID, disclosed as forced answers.
    ranked = sorted(rows, key=lambda r: (-r['confidence'], digest(r['id'])))
    k = int(len(ranked)*fraction)
    chosen = ranked[:k]
    wrong = 0
    forced = 0
    for r in chosen:
        p = r['pred']
        if p == 0:
            forced += 1
            p = 1 if int(digest(r['id'])[-1], 16) % 2 else -1
        wrong += p != labels[r['id']]['truth']
    return dict(answered=k, wrong=wrong, selective_error=wrong/k, forced_ties=forced)

def tests():
    def e(i, vote, origin, text='same'):
        return dict(id=str(i), vote=vote, origin=origin, text=text, url='u'+str(i))
    a, b = e(0, 1, 'a'), e(1, -1, 'b', 'other')
    p1 = aggregate([a, b], 'group')
    p2 = aggregate([a, b, e(2, 1, 'a')], 'group')
    assert p1 == p2, 'homogeneous duplicate should not increase group weight'
    assert aggregate([a,b,e(2,1,'a')], 'raw')[0] == 1
    assert aggregate([e(0,1,None)], 'group') == (1,1)
    assert aggregate([a,b], 'group') == (0,0)
    c = dict(id='x', split='dev', initial=[a,b], candidates=[e(2,-1,'a'),e(3,1,'c')])
    original = choose(c, 'group_novelty')
    c['candidates'][0]['vote'] *= -1
    assert choose(c, 'group_novelty')['selected'] == original['selected'] == 1
    assert set(c['initial'][0]) == {'id','vote','origin','text','url'}
    # Counterexample: false merging suppresses legitimate independent support.
    before = [e(0,1,'a'),e(1,1,'b'),e(2,-1,'c')]
    after = [e(0,1,'merged'),e(1,1,'merged'),e(2,-1,'c')]
    assert aggregate(before,'group')[0] == 1
    assert aggregate(after,'group')[0] == 0
    return ['homogeneous_duplicate_invariance','raw_duplicate_counterexample','missing_origin','tie_abstention','selection_no_vote_peeking','policy_schema','false_merge_counterexample']

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', required=True)
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    passed = tests()
    public, private = generate()
    devroots = {r for c in public if c['split']=='dev' for r in private[c['id']]['roots'].values()}
    testroots = {r for c in public if c['split']=='test' for r in private[c['id']]['roots'].values()}
    assert not devroots & testroots
    (out/'method_cases.json').write_text(json.dumps(public, indent=2))
    (out/'method_eval_labels.json').write_text(json.dumps(private, indent=2))
    results, predictions = [], []
    for regime in REGIMES:
        cases = corrupt(public, regime)
        for method in METHODS:
            rows = []
            for case in cases:
                if method == 'oracle':
                    # Isolated diagnostic, never supplied to deployable policy.
                    oracle_case = json.loads(json.dumps(case))
                    for e in oracle_case['initial'] + oracle_case['candidates']:
                        e['origin'] = private[case['id']]['roots'][e['id']]
                    r = choose(oracle_case, 'group')
                else:
                    r = choose(case, method)
                r.update(method=method, regime=regime)
                rows.append(r)
            dev = [r for r in rows if r['split']=='dev']
            test = [r for r in rows if r['split']=='test']
            threshold = calibrate(dev, private)
            results.append(dict(regime=regime, method=method, threshold=threshold,
                                test=metrics(test, private, threshold),
                                uncalibrated=metrics(test, private),
                                matched_80=matched(test, private)))
            predictions.extend(rows)
    (out/'method_predictions.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in predictions))
    payload = dict(kind='synthetic_mechanism_replay_NOT_LLM_results', seed=SEED,
                   n_cases=len(public), n_dev=200, n_test=400,
                   accuracy_assumption=.72, corruption_probability=.6,
                   shortlist_metadata_count=5, initial_records=8, max_returned_records=9,
                   text_similarity_threshold=.94, dev_error_target=.1,
                   tests_passed=passed+['root_disjoint_split'],
                   python=platform.python_version(), seconds=time.perf_counter()-started,
                   results=results,
                   artifacts_sha256={name:hashlib.sha256((out/name).read_bytes()).hexdigest() for name in ['method_cases.json','method_eval_labels.json','method_predictions.jsonl']})
    (out/'method_results.json').write_text(json.dumps(payload, indent=2))
    with (out/'method_summary.csv').open('w',newline='') as f:
        writer=csv.writer(f)
        writer.writerow(['regime','method','matched80_wrong','matched80_answered','forced_ties','calibrated_answered','calibrated_wrong','mean_calls'])
        for x in results:
            writer.writerow([x['regime'],x['method'],x['matched_80']['wrong'],x['matched_80']['answered'],x['matched_80']['forced_ties'],x['test']['answered'],x['test']['wrong'],x['test']['mean_calls']])
    print(json.dumps({k:v for k,v in payload.items() if k != 'results'}, indent=2))
    print((out/'method_summary.csv').read_text())

if __name__ == '__main__':
    main()
