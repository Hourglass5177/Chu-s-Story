from pathlib import Path
root=Path(__file__).resolve().parents[1]
for p in (root/'tests').rglob('*.gd'):
    t=p.read_text(encoding='utf-8'); before=t
    t=t.replace('in 241: task._process(1.0/120.0)','in 361: task._process(1.0/120.0)')
    t=t.replace('tick(task,2.1)','tick(task,3.1)').replace('_drive(task, 2.1)','_drive(task, 3.1)')
    t=t.replace('task._process(2.1)','task._process(3.1)').replace('2.6 if tutorial else 2.1','2.6 if tutorial else 3.1')
    if p.name=='test_heritage_input_profile.gd': t=t.replace('Vector2(6,0)','Vector2(20,0)')
    if p.name=='test_action_story_v3.gd':
        t=t.replace('test_paper_three_real','test_paper_four_real').replace('actual_three_contours','actual_four_contours')
        t=t.replace('for contour: int in 3:', 'for contour: int in 4:').replace('for index: int in 3:', 'for index: int in 4:')
        t=t.replace('decode_contours(source).size(),3','decode_contours(source).size(),4')
        t=t.replace('\t\t\tif contour==1: task.size = Vector2(1920,1080)\n\t\tassert_eq(results.size(),1)', '\t\t\tif contour==1: task.size = Vector2(1920,1080)\n\t\tassert_eq(results.size(),0,"Cut closure starts the reveal, not the result")\n\t\t_tick(task,1.1)\n\t\tassert_eq(results.size(),1)')
        t=t.replace('\t\t\tassert_eq(task.segment,index+1,"Joypad=%s, distance=%s/%s"%[joypad,task.cut_distance,task.cut_length])\n\t\tassert_eq', '\t\t\tassert_eq(task.segment,index+1,"Joypad=%s, distance=%s/%s"%[joypad,task.cut_distance,task.cut_length])\n\t\t_tick(task,1.1)\n\t\tassert_eq')
    if p.name=='test_heritage_television_host.gd': t=t.replace('5 if id == &"gu_pen_ge" else 4','5 if id in [&"gu_pen_ge",&"ezhou_diaohua_jianzhi"] else 4')
    if t!=before:p.write_text(t,encoding='utf-8')
