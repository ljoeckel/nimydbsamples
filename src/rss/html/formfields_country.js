class CountryCodeField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="form-group">
            <label for="id">Code</label>
            <input
                id="id"
                data-init="document.getElementById('id')" 
                data-bind:id type="text"
                pattern="[A-Z]{2,3}"
                maxLength="3"
                data-on:input__debounce.500ms="@post('/get-country')"
                required
                />
        </div>`;
    }
}

class CountryNameField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="form-group">
            <label for="country">Country</label>
            <input
                id="country"
                data-init="document.getElementById('country')" 
                data-bind:country type="text"
                required
                />
        </div>`;
    }
}


class CountryPrefixField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="form-group">
            <label for="calling_code">Prefix +</label>
            <input
                id="calling_code"
                data-init="document.getElementById('calling_code')" 
                data-bind:calling_code type="text"
                pattern="[0-9]{1,3}"
                maxLength="3"
                required
                />
        </div>`;
    }
}

customElements.define('country-name', CountryNameField);
customElements.define('country-code', CountryCodeField);
customElements.define('country-prefix', CountryPrefixField);
