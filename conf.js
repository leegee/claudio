let SpecReporter = require('jasmine-spec-reporter').SpecReporter;

exports.config = {
  jasmineNodeOpts: {
    print: function () {}
  },
  framework: 'jasmine',
  seleniumAddress: 'http://localhost:4444/wd/hub',
  specs: ['tests/one.spec.js'],

  onPrepare: function () {
    jasmine.getEnv().addReporter(
      new SpecReporter({
        spec: {
          displayStacktrace: false
        }
      })
    );
  }
}

