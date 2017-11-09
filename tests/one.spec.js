require('../.env.js');

var EC = protractor.ExpectedConditions;

describe('Environment', () => {
    it('should have username', () => {
        expect(process.env.IZEL_GMAIL_USER).not.toBe(undefined);
    })
    it('should have username', () => {
        expect(process.env.IZEL_GMAIL_PASS).not.toBe(undefined);
    })
});

describe('Map Uploader', () => {
    beforeEach(() => {
        browser.waitForAngularEnabled(false);
    });

    it('should have a title', () => {
        browser.get('http://localhost/index.html');
        expect(browser.getTitle()).toEqual('Map Uploader');
    });

    it('can sign in', () => {
        browser.wait(EC.elementToBeClickable($('#auth-button')), 5000);
        browser.driver.findElement(by.css('#auth-button')).then(el => {
            el.click();
        }).then(() => {
            loginWithGoogle(
                process.env.IZEL_GMAIL_USER,
                process.env.IZEL_GMAIL_PASS
            );
            // return browser.driver.wait( function(){ 1===3}, 100000 )
        })
    })
});


/**
  * Uses the dreaded `sleep` method because finding the password
  * by any css selector tried fails.
  * @param {string} username - A Google username.
  * @param {string} passphrase - A Google passpharse.
  * @return {Promise.<void>} Promise resolved when logged in.
  */
var loginWithGoogle = function (username, passphrase) {
    return selectWindow(1).then(() => {
        return browser.driver.findElement(by.css('[type="email"]'))
            .then((el) => {
                el.sendKeys(username + protractor.Key.ENTER);
            }).then(() => {
                browser.driver.sleep(1000);
            }).then(() => {
                browser.actions().sendKeys(passphrase + protractor.Key.ENTER).perform();
            });
    })
}

/**
* Focus the browser to the specified  window.
* [Implementation by and thanks to]{@link http://stackoverflow.com/questions/21700162/protractor-e2e-testing-error-object-object-object-has-no-method-getwindowha}
* @param  {Number} index The 0-based index of the window (eg 0=main, 1=popup)
* @return {webdriver.promise.Promise.<void>} Promise resolved when the index window is focused.
*/
var selectWindow = (index) => {
    browser.driver.wait(function () {
        return browser.driver.getAllWindowHandles().then((handles) => {
            if (handles.length > index) {
                return true;
            }
        });
    });

    return browser.driver.getAllWindowHandles().then((handles) => {
        return browser.driver.switchTo().window(handles[index]);
    });
};



