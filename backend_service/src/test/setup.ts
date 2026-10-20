// Loaded before every test file (node --import). The suites call the API with
// the developer bypass token, which is only honoured when explicitly switched
// on, so this is where it is switched on, for tests alone.
process.env.NODE_ENV = 'test';
process.env.DEV_AUTH_BYPASS = '1';
process.env.DEV_AUTH_BYPASS_TOKEN = 'mock-test-token';
process.env.DEV_AUTH_BYPASS_USER_ID = '00000000-0000-0000-0000-000000000000';
