import React from 'react'
import { Link } from 'react-router'
import { Button, List } from 'semantic-ui-react'

import { systemFunction as sF } from '../../../helpers/checkPermissions'
import statUnitIcons from '../../../helpers/statUnitIcons'
import statUnitTypes from '../../../helpers/statUnitTypes.js'

export default ({ deleteStatUnit, ...statUnit }) => {
  const handleDelete = () => {
    if (confirm(`Delete StatUnit '${statUnit.name}'. Are you sure?`)) {
      deleteStatUnit(statUnit.id)
    }
  }
  const address = statUnit.address
    ? Object.values(statUnit.address).join(' ')
    : ''
  const title = statUnitTypes.find(x => statUnit.type === x.key).value
  return (
    <List.Item>
      <List.Icon
        name={statUnitIcons(statUnit.type)}
        size="large"
        verticalAlign="middle"
        title={title}
      />
      <List.Content>
        <List.Header
          content={sF('StatUnitDelete')
            ? <Link to={`/statunits/edit/${statUnit.regId}`}>{statUnit.name}</Link>
            : <span>{statUnit.name}</span>}
        />
        <List.Description>
          <span>{address}</span>
          {sF('StatUnitDelete') && <Button onClick={handleDelete} negative>delete</Button>}
        </List.Description>
      </List.Content>
    </List.Item>
  )
}
