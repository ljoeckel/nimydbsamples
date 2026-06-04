class UserIdField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="form-group">
            <div>
                <label for="name">Userid</label>
                <small class="error" data-show="$useridInvalid">Userid is already registered. </small>
            </div>
            <input
                id="userid"
                data-bind:userid type="text"
                data-class="{'input-error': $useridInvalid}"
                data-on:input__debounce.500ms="@post('/validate-userid')"
                required
                placeholder="Your Userid" autofocus />
        </div>`;
    }
}

class NameField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="form-group">
            <label for="name">Name</label>
            <input
                id="name"
                data-bind:name type="text"
                required
                placeholder="Your Name" autofocus />
        </div>`;
    }
}

class EmailField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="form-group">
                <div>
                    <label for="email">Email</label>
                    <small class="error" data-show="$emailInvalid">E-Mail address already registered. </small>
                </div>
                <input 
                    id="email" 
                    data-bind:email /* if emailInvalid is true class 'input-error' will be added */
                    data-class="{'input-error': $emailInvalid}"
                    data-on:input__debounce.500ms="@post('/validate-email')"
                    type="email"
                    required />
                <small class="hint">Enter a valid E-Mail address</small>
            </div>
        `;
    }
}


class PasswordField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="form-group">
                <label for="password">Password</label>
                <input 
                    id="password" 
                    name="password" 
                    data-bind:password type="password" 
                    placeholder="••••••••"
                    autocomplete="new-password" />
                <small class="hint">Use at least 8 characters.</small>
            </div>
        `;
    }
}

class CountryField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="form-group">
                <label for="country">Country</label>
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
                <small class="hint">This helps us show localized content.</small>
            </div>
        `;
    }
}

class TermsField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="form-group checkbox full">
                <label>
                    <input 
                        type="checkbox" 
                        data-bind:terms />
                    I agree to the terms and conditions
                </label>
                <label> </label>
            </div>
        `;
    }
}

class PlanField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
            <div class="form-group full">
                <span class="section-title">Choose Plan</span>

                <div class="form-group checkbox">
                    <!-- data-bind both on 'plan' -->
                    <label>
                        <input type="radio" value="starter" data-bind:plan />Starter (Free)
                    </label>
                </div>

                <div class="form-group checkbox">
                    <label>
                        <input type="radio" value="pro" data-bind:plan />Pro (Paid)
                    </label>
                </div>
            </div>
        `;
    }
}

class StatusField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="form-group">
            <label for="status">Status</label>
            <input id="status" data-bind:status name="status" type="text" readonly />
        </div>
        `;
    }
}

class TimeField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="form-group">
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