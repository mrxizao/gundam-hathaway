extends Node
## 批 6 窄入口：只跑任务评价相关套件，改一个数不用等 3 分钟的全量。

func _ready() -> void:
	var t := T.new()
	SuiteMissionRating.run(t, self)
	SuiteLayout.run(t, self)
	SuiteUiStyle.run(t, self)
	t.report()
	get_tree().quit()
