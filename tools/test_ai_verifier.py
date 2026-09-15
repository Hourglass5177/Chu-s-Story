import importlib.util,json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('verifier',Path('tools/verify_ai_difficulties.py').resolve())
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
class EvidenceSafety(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.original=v.ROOT;v.ROOT=self.root
 def tearDown(self):v.ROOT=self.original;self.tmp.cleanup()
 def invoke(self,*args):
  with patch('sys.argv',['verify',*args]),patch.object(v,'keep_awake'):
   v.main()
 def test_existing_evidence_untouched(self):
  out=self.root/'artifacts/ai-difficulties-final';out.mkdir(parents=True);p=out/'source-hashes.json';p.write_text('sentinel')
  with self.assertRaises(SystemExit) as caught:self.invoke()
  self.assertEqual(caught.exception.code,2);self.assertEqual(p.read_text(),'sentinel')
 def test_reject_outside_artifacts(self):
  with self.assertRaises(SystemExit):self.invoke('--output-dir','outside')
  self.assertFalse((self.root/'outside').exists())
 def test_reject_unknown_before_write(self):
  with self.assertRaises(SystemExit):self.invoke('--only','typo')
  self.assertFalse((self.root/'artifacts').exists())
 def test_reject_zero_workers(self):
  with self.assertRaises(SystemExit):self.invoke('--workers','0')
 def test_new_directory_and_command_destination(self):
  seen=[]
  with patch.object(v,'run_job',side_effect=lambda *args:seen.append(args[0][0])),patch.object(v,'sources',return_value={'a':'hash'}),patch.object(v,'summarize',return_value=True):
   self.invoke('--output-dir','artifacts/new-version','--only','pair-01-unified','--workers','1')
  self.assertEqual(seen,['pair-01-unified']);self.assertEqual(v.output_resource('part.json'),'res://artifacts/new-version/part.json')
  self.assertEqual(json.loads((v.OUT/'source-hashes.json').read_text()),{'a':'hash'})
 def test_resume_rejects_source_change(self):
  out=self.root/'artifacts/ai-difficulties-final';out.mkdir(parents=True);(out/'source-hashes.json').write_text('{}')
  with patch.object(v,'sources',return_value={'changed':'hash'}),self.assertRaisesRegex(AssertionError,'Sources changed'):
   self.invoke('--resume')
 def test_selected_batch_rejects_midrun_changes(self):
  current={'a':'before'}
  def change(*args):current['a']='after'
  with patch.object(v,'run_job',side_effect=change),patch.object(v,'sources',side_effect=lambda:dict(current)):
   with self.assertRaisesRegex(RuntimeError,'Sources changed during validation'):
    self.invoke('--output-dir','artifacts/changed-during-run','--only','pair-01-unified','--workers','1')
 def test_actual_command_uses_separate_directory(self):
  v.OUT=self.root/'artifacts/separate';v.OUT.mkdir(parents=True)
  (v.OUT/'source-hashes.json').write_text('{}')
  with patch.object(v,'sources',return_value={}),patch.object(v,'validate'),patch.object(v.subprocess,'run') as run:
   run.return_value.returncode=0
   v.run_job(('pair-01-unified',288,['--pair=0,1','--unified-chance']),'godot',930017)
  self.assertIn('--output=res://artifacts/separate/pair-01-unified.json',run.call_args.args[0])
 def test_selected_batch_enforces_acceptance_gate(self):
  with patch.object(v,'run_job'),patch.object(v,'sources',return_value={}),patch.object(v,'summarize',return_value=False) as summary:
   with self.assertRaises(SystemExit) as caught:
    self.invoke('--only','pair-01-unified','--workers','1')
  self.assertEqual(caught.exception.code,1)
  self.assertEqual([j[0] for j in summary.call_args.args[0]],['pair-01-unified'])
 def test_partial_summary_reports_strength_failure_without_other_batches(self):
  v.OUT=self.root/'artifacts/partial';v.OUT.mkdir(parents=True)
  (v.OUT/'source-hashes.json').write_text('{}')
  row={'decision_times_us':[1000], 'turns':10, 'end_reason':0, 'winner_seats':[0], 'difficulties':[0,1]}
  with patch.object(v,'validate',return_value=[dict(row) for _ in range(4)]),patch.object(v,'sources',return_value={}):
   self.assertFalse(v.summarize([('pair-01-unified',4,[])]))
  report=json.loads((v.OUT/'summary-selected.json').read_text())
  self.assertFalse(report['full_matrix']);self.assertEqual(report['games'],4)
  self.assertEqual(len(report['failures']),1)
  self.assertIn('55%',report['failures'][0])
 def test_summary_only_respects_selected_batch(self):
  with patch.object(v,'summarize',return_value=True) as summary,patch.object(v,'run_job') as run:
   with self.assertRaises(SystemExit) as caught:self.invoke('--summarize','--only','pair-01-unified')
  self.assertEqual(caught.exception.code,0);run.assert_not_called()
  self.assertEqual([j[0] for j in summary.call_args.args[0]],['pair-01-unified'])
if __name__ == '__main__':
 unittest.main(verbosity=2)
