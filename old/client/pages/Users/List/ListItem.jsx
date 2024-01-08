import React from 'react'
import { arrayOf, number, string, func, shape } from 'prop-types'
import { Table } from 'semantic-ui-react'
import { Link } from 'react-router'

import { checkSystemFunction as sF } from '/helpers/config'
import { formatDateTime } from '/helpers/dateHelper'
import { userStatuses } from '/helpers/enums'
import RegionTree from '/components/RegionTree'
import ColumnActions from './ColumnActions.jsx'

const ListItem = ({
  id,
  name,
  description,
  roles,
  creationDate,
  status,
  regions,
  regionsTree,
  getFilter,
  setUserStatus,
  localize,
}) => (
  <Table.Row textAlign="center">
    <Table.Cell>{sF('UserEdit') ? <Link to={`/users/edit/${id}`}>{name}</Link> : name}</Table.Cell>
    <Table.Cell content={description} />
    <Table.Cell content={<span>{localize(roles.map(v => v.name).join(', '))}</span>} />
    <Table.Cell content={<span>{creationDate && formatDateTime(creationDate)}</span>} />
    <Table.Cell content={<span> {localize(userStatuses.get(Number(status)))}</span>} />
    <Table.Cell>
      {regions.length > 0 && (
        <RegionTree
          name="RegionTree"
          label="Regions"
          dataTree={regionsTree}
          checked={regions}
          isView
        />
      )}
    </Table.Cell>
    <Table.Cell>
      <ColumnActions
        id={id}
        name={name}
        status={status}
        localize={localize}
        setUserStatus={setUserStatus}
        getFilter={getFilter}
      />
    </Table.Cell>
  </Table.Row>
)

ListItem.propTypes = {
  id: string.isRequired,
  name: string.isRequired,
  description: string,
  localize: func.isRequired,
  roles: arrayOf(shape({})).isRequired,
  creationDate: string.isRequired,
  status: number.isRequired,
  regions: arrayOf(string),
  regionsTree: shape({}).isRequired,
  getFilter: func.isRequired,
  setUserStatus: func.isRequired,
}

ListItem.defaultProps = {
  description: '',
  regions: [],
}

export default ListItem
