// Conventional Commits + every commit must reference an issue (Closes #12, Refs #12...)
// Only three types, one per kind of branch: feature/ -> feat, bug/ -> fix, tech/ -> chore
export default {
	extends: ["@commitlint/config-conventional"],
	rules: {
		"type-enum": [2, "always", ["feat", "fix", "chore"]],
		"references-empty": [2, "never"],
	},
	// Release commits made by release-please don't reference an issue
	ignores: [(message) => /^chore(\([^)]*\))?: release /.test(message)],
};
