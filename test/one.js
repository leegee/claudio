describe('Environment', () => {
    it('should have username', () => {
        expect( process.env.IZEL_GMAIL_USER ).not.toBe(undefined);
    })
    it('should have username', () => {
        expect( process.env.IZEL_GMAIL_PASS ).not.toBe(undefined);
    })
});

describe('Map Uploader', () => {
    beforeEach( () => {
        browser.waitForAngularEnabled(false);
    });

    it('should have a title', () => {
        browser.get('http://localhost/index.html');
        expect(browser.getTitle()).toEqual('Map Uploader');
    });

    it('has a sign in button', () => {
        browser.driver.findElement(by.css('#sign-in')).then( elem => {
            elem.click();
        }).then( () => {
            loginWithGoogle();
            return browser.driver.wait( function(){ 1===3}, 100000 )
        })
    })

});


/**
 * [selectWindow Focus the browser to the index window. 
 * Implementation by http://stackoverflow.com/questions/21700162/protractor-e2e-testing-error-object-object-object-has-no-method-getwindowha]
 * @param  {[Object]} index [Is the index of the window. E.g., 0=browser, 1=FBpopup]
 * @return {[!webdriver.promise.Promise.<void>]}       [Promise resolved when the index window is focused.]
 */
var selectWindow = (index) => {
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
    selectWindow(1).then( () => {
        return browser.driver.wait( () => {
            browser.driver.findElement(by.css('#identifierId')).then( (elem) => {
                elem.sendKeys( process.env.IZEL_GMAIL_USER );
            }).then( () => {
                // browser.driver.sendKeys( process.env.IZEL_GMAIL_PASS );
            });
        }, 100000)
    })
}
