import React from 'react'
import { Link } from 'react-router'
import { Button, List } from 'semantic-ui-react'

import { systemFunction as sF } from 'helpers/checkPermissions'
import statUnitIcons from 'helpers/statUnitIcons'
import statUnitTypes from 'helpers/statUnitTypes'

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
          content={sF('StatUnitEdit')
            ? <Link to={`/statunits/view/${statUnit.regId}`}>{statUnit.name}</Link>
            : <span>{statUnit.name}</span>}
        />
        <List.Description>
          <span>{address}</span>
          {sF('StatUnitDelete') && <Button onClick={handleDelete} negative>delete</Button>}
          {sF('StatUnitEdit') && <Link to={`/statunits/edit/${statUnit.regId}`}>edit</Link>}
        </List.Description>
      </List.Content>
    </List.Item>
  )
}
