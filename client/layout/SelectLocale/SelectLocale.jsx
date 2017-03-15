import React from 'react'
import { Dropdown, Flag } from 'semantic-ui-react'

import { locales } from 'helpers/locale'

const SelectLocale = ({ locale, selectLocale }) => {
  const trigger = <Flag name={locales.find(x => x.key === locale).flag} />
  const handleSelect = value => () => {
    window.localStorage.setItem('locale', value)
    selectLocale(value)
  }
  return (
    <Dropdown
      trigger={trigger}
      className="item"
      icon="caret down"
      simple
    >
      <Dropdown.Menu>
        {locales.map(({ key, flag, text }) => (
          <Dropdown.Item
            key={key}
            onClick={handleSelect(key)}
            selected={key === locale}
          >
            <Flag name={flag} />
            {text}
          </Dropdown.Item>
        ))}
      </Dropdown.Menu>
    </Dropdown>
  )
}

const { func, string } = React.PropTypes

SelectLocale.propTypes = {
  locale: string.isRequired,
  selectLocale: func.isRequired,
}

export default SelectLocale
