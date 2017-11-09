var fs = require('fs');
var chai = require('chai');
var expect = chai.expect;

require('../.env.js');
var TestConfig = require('./TestConfig.js');

describe('Map Updater', function () {
    before(function (client, done) {
        done();
    });

    after(function (client, done) {
        client.end(function () {
            done();
        });
    });

    afterEach(function (client, done) {
        done();
    });

    beforeEach(function (client, done) {
        done();
    });

    describe('Test environment', function () {
        it('has expected env var', function (browser) {
            expect(process.env.IZEL_GMAIL_USER).not.to.be.an('undefined');
            expect(process.env.IZEL_GMAIL_PASS).not.to.be.an('undefined');
            browser.end();
        });
        it('has fixtures', function (browser) {
            expect(fs.existsSync(TestConfig.input.skus.small)).to.be.true;
            browser.end();
        });
    });

    describe('Sign in', () => {
        // beforeEach(function (client, done) {
        //     browser.waitForAngularEnabled(false);
        //     done();
        // });

        it('should have a title', (browser) => {
            browser.url('http://localhost/index.html');
            expect(browser.getTitle()).equal('Map Uploader');
        });

        it('has a sign in button', (browser) => {
            browser.driver.findElement(by.css('#auth-button')).then( el => {
                el.click();
            }).then( () => {
                loginWithGoogle();
                return browser.driver.wait( function(){ 1===3}, 1000 )
            })
        })
    });


    describe('Main', function () {
        it('runs', function (browser) {
            browser
                .url('http://localhost')
                .waitForElementVisible('body', 4000)
                .waitForElementVisible('input#skus', 30000)
                .setValue('input#skus', TestConfig.input.skus.small)
                // .click('button[name=btnG]')
                // .pause(1000)
                .assert.containsText('#main', 'Night Watch')
                .end();
        })
    });
});

/*
 * [selectWindow Focus the browser to the index window.
 * Implementation by http://stackoverflow.com/questions/21700162/protractor-e2e-testing-error-object-object-object-has-no-method-getwindowha]
 * @param  {browser} browser
 * @param  {[Object]} index Iindex of the window. Eg: 0=browser, 1=FBpopup
 * @return {[!webdriver.promise.Promise.<void>]} Promise resolved when the index window is focused.
 */
var selectWindow = (browser, index) => {
  browser.driver.wait(function() {
      return browser.driver.getAllWindowHandles().then( (handles) => {
          if (handles.length > index) {
              return true;
          }
      });
  });

  return browser.driver.getAllWindowHandles().then( (handles) => {
      return browser.driver.switchTo().window(handles[index]);
  });
};

var loginWithGoogle = function () {
  selectWindow(browser,1).then( () => {
      return browser.driver.wait( () => {
          browser.driver.findElement(by.css('#identifierId')).then( (elem) => {
              elem.sendKeys( process.env.IZEL_GMAIL_USER );
          }).then( () => {
              browser.driver.findElement(by.buttonText('NEXT')).then( (elem) => {
                  elem.click();
              });
          }).then( () => {
              browser.driver.sleep(1000);
              browser.driver.sendKeys( process.env.IZEL_GMAIL_PASS );
          });
      }, 100000)
  })
}

