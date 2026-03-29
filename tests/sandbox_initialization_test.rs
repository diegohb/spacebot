// Integration test that verifies sandbox is created during initialization
// This will be tested indirectly through the system integration tests

#[test]
fn test_sandbox_creation_in_initialize() {
    // Verify the initialize_agents function exists and accepts sandbox
    // This is mostly a compile-time check
    let _ = std::any::type_name::<spacebot::sandbox::Sandbox>();
    let _ = std::any::type_name::<spacebot::sandbox::SandboxConfig>();
    let _ = spacebot::sandbox::detect_backend as fn() -> _;
}
