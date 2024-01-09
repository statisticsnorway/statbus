import React, { useState, useEffect } from 'react'
import PropTypes from 'prop-types'
import { Table, Confirm } from 'semantic-ui-react'
import { equals } from 'ramda'

import Paginate from '/components/Paginate'
import TableHeader from './Table/TableHeader.jsx'
import ListItem from './ListItem.jsx'

function RolesList({ localize, toggleRole, fetchRoles, totalCount, query, roles: initialRoles }) {
  const [showConfirm, setShowConfirm] = useState(false)
  const [selectedId, setSelectedId] = useState(undefined)
  const [selectedStatus, setSelectedStatus] = useState(undefined)
  const [roles, setRoles] = useState(initialRoles)

  useEffect(() => {
    fetchRoles(query)
  }, [fetchRoles, query])

  useEffect(() => {
    if (!equals(roles, initialRoles)) {
      setRoles(initialRoles)
    }
  }, [initialRoles])

  const handleToggle = (id, status) => () => {
    setSelectedId(id)
    setSelectedStatus(status)
    setShowConfirm(true)
  }

  const handleConfirm = () => {
    const id = selectedId
    const status = selectedStatus
    setShowConfirm(false)
    setSelectedId(undefined)
    setSelectedStatus(undefined)
    toggleRole(id, status ? 0 : 1)
  }

  const handleCancel = () => {
    setShowConfirm(false)
  }

  const renderConfirm = () => {
    const { name: confirmName } = roles.find(r => r.id === selectedId)
    const msgKey = selectedStatus ? 'DeleteRoleMessage' : 'UndeleteRoleMessage'
    return (
      <Confirm
        open={showConfirm}
        header={`${localize('AreYouSure')}`}
        content={`${localize(msgKey)} "${confirmName}"?`}
        onConfirm={handleConfirm}
        onCancel={handleCancel}
      />
    )
  }

  return (
    <div>
      {showConfirm && renderConfirm()}
      <h2>{localize('RolesList')}</h2>
      <Paginate totalCount={totalCount}>
        <Table selectable>
          <TableHeader localize={localize} />
          {roles &&
            roles.map(r => (
              <ListItem
                key={r.id}
                {...r}
                onToggle={handleToggle(r.id, r.status)}
                localize={localize}
              />
            ))}
        </Table>
      </Paginate>
    </div>
  )
}

RolesList.propTypes = {
  localize: PropTypes.func.isRequired,
  toggleRole: PropTypes.func.isRequired,
  fetchRoles: PropTypes.func.isRequired,
  totalCount: PropTypes.number.isRequired,
  query: PropTypes.shape({}).isRequired,
  roles: PropTypes.arrayOf(PropTypes.shape({
    id: PropTypes.string.isRequired,
    name: PropTypes.string.isRequired,
    description: PropTypes.string.isRequired,
    activeUsers: PropTypes.number.isRequired,
    status: PropTypes.number.isRequired,
  })).isRequired,
}

export default RolesList
