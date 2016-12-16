const langs = window.__initialStateFromServer.allLanguages
const locale = 'ky-KG' // get from localStorage

export default key => langs[locale][key]
