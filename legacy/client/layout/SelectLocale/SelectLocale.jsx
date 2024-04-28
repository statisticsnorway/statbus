import React from 'react'
import { func, string } from 'prop-types'
import { Dropdown, Flag } from 'semantic-ui-react'

import { getFlag, setLocale, requestToChangeLocale } from '/helpers/locale'
import config from '/helpers/config'

const SelectLocale = ({ locale, selectLocale }) => {
  const trigger = <Flag name={getFlag(locale)} />
  const handleSelect = value => () => {
    setLocale(value)
    selectLocale(value)
    requestToChangeLocale(value)
  }
  return (
    <Dropdown trigger={trigger} className="item" icon="caret down" simple>
      <Dropdown.Menu>
        {config.locales.map(({ Key, Text }) => (
          <Dropdown.Item key={Key} onClick={handleSelect(Key)} selected={Key === locale}>
            <Flag name={getFlag(Key)} />
            {Text}
          </Dropdown.Item>
        ))}
      </Dropdown.Menu>
    </Dropdown>
  )
}

SelectLocale.propTypes = {
  locale: string.isRequired,
  selectLocale: func.isRequired,
}

export default SelectLocale
