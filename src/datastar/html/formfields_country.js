class CountryNameField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="form-group">
            <label for="cname">Name</label>
            <input
                id="cname"
                data-init="document.getElementById('cname').focus()" 
                data-bind:cname type="text"
                required
                autofocus />
        </div>`;
    }
}

class CountryCodeField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="form-group">
            <label for="ccode">Code</label>
            <input
                id="ccode"
                data-init="document.getElementById('ccode').focus()" 
                data-bind:ccode type="text"
                required
                />
        </div>`;
    }
}

class CountryPrefixField extends HTMLElement {
    connectedCallback() {
        this.innerHTML = `
        <div class="form-group">
            <label for="cprefix">Prefix</label>
            <input
                id="cprefix"
                data-init="document.getElementById('cprefix').focus()" 
                data-bind:cprefix type="text"
                required
                />
        </div>`;
    }
}

customElements.define('country-name', CountryNameField);
customElements.define('country-code', CountryCodeField);
customElements.define('country-prefix', CountryPrefixField);
