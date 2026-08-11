
class UserIdField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="field">
                <label class="label">
                    Userid
                    <small class="has-text-danger" data-show="$useridInvalid">already registered.</small>
                </label>
            <div class="control">
                <input class="input" type="text" required minlength="3"
                    id="userid"
                    data-bind:userid type="text"
                    data-class="{'is-danger': $useridInvalid}"
                    data-on:input__debounce.500ms="@post('/validate-userid')"
                    required
                    placeholder="Your Userid" autofocus />
            </div>
            <p class="help">The 'userid' will be used to login.</p>
            </div>
        </div>`;
    }
}


class NameField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="field">
                <label class="label">
                    Name
                </label>
                <div class="control">
                    <input class="input" type="text" required minlength="3"
                        id="name"
                        data-bind:name
                        required
                        placeholder="Your Name" autofocus />
                </div>
            </div>
        </div>`;
    }
}


class EmailField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="field">
                <label class="label">
                    EMail
                    <small class="has-text-danger" data-show="$emailInvalid">already registered.</small>                
                </label>
                <div class="control">
                    <input class="input" type="email" required minlength="8"
                        id="email" 
                        data-bind:email
                        data-class="{'is-danger': $emailInvalid}"
                        data-on:input__debounce.500ms="@post('/validate-email')"
                    />
                </div>
            </div>
        </div>`;
    }
}



class PasswordField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="field">
                <label class="label">
                    Password
                </label>
                <div class="control">
                    <input class="input" type="password" required minlength="8"
                        id="password" 
                        name="password" 
                        data-bind:password
                        placeholder="••••••••"
                        autocomplete="new-password" />
                    <small class="hint">Use at least 8 characters.</small>
                </div>
            </div>
        `;
    }
}

class CountryField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="field">
                <label class="label">
                    Country
                </label>
                <div class="select">
                    <select
                        id="country" 
                        name="country" 
                        data-bind:country
                        autocomplete="country-name">
                            <option value="" selected disabled>Select country</option>
                            <option>Switzerland</option>
                            <option>Germany</option>
                            <option>Spain</option>
                            <option>Canada</option>
                            <option>Australia</option>
                            <option>USA</option>
                            </select>
                </div>
                <p class="help"><small>This helps us show localized content.</small></p>
            </div>
        `;
    }
}

class TermsField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="field">
                <div class="control>
                    <label class="checkbox">
                        <input type="checkbox" data-bind:terms />
                        I agree to the terms and conditions
                    </label>
                </div>
            </div>
        `;
    }
}

class PlanField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="field">
                <div class="control">
                    <label class="label">
                        Choose Plan
                    </label>
                    <label class="radio">
                        <input type="radio" value="starter" data-bind:plan /> Starter (Free)
                    </label>
                    <label class="radio">
                        <input type="radio" value="pro" data-bind:plan /> Pro (Paid)
                    </label>
                </div>
            </div>
        `;
    }
}

class StatusField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="field">
            <label for="status">Status</label>
            <input id="status" data-bind:status name="status" type="text" readonly />
        </div>
        `;
    }
}

class TimeField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="field">
            <label for="time">Last update</label>
            <input id="time" data-bind:time name="time" type="text" readonly />
        </div>
        `;
    }
}

customElements.define('userid-field', UserIdField);
customElements.define('name-field', NameField);
customElements.define('email-field', EmailField);
customElements.define('password-field', PasswordField);
customElements.define('country-field', CountryField);
customElements.define('terms-field', TermsField);
customElements.define('plan-field', PlanField);
customElements.define('status-field', StatusField);
customElements.define('time-field', TimeField);