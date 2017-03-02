import React from 'react'

import { wrapper } from 'helpers/locale'

const ListItem = ({ localize, statUnit, restore }) => {
  const handleRestore = () => {
    const msg = `${localize('UndeleteMessage')}. ${localize('AreYouSure')}`
    if (confirm(msg)) {
      restore(statUnit.regId)
    }
  }

  return (
    <div>
      {statUnit.name}
      <button onClick={handleRestore}>{localize('Restore')}</button>
    </div>
  )
}

const { number, string, func, shape } = React.PropTypes

ListItem.propTypes = {
  localize: func.isRequired,
  restore: func.isRequired,
  statUnit: shape({
    regId: number.isRequired,
    name: string.isRequired,
  }).isRequired,
}

export default wrapper(ListItem)
