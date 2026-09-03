package release

// Test constructors: a Scenario is normally obtained only from the directory
// listing at a commit (ScenariosAt / ParseScenario). Tests of the pure
// algorithm need values without a git tree, so they say which home a name has
// explicitly. Nothing outside _test files may build a Scenario this way.
func arc(name string) Scenario   { return Scenario{Name: name, Home: WorkflowArcs} }
func fleet(name string) Scenario { return Scenario{Name: name, Home: WorkflowFleet} }
