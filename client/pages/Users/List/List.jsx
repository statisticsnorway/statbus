import React from 'react'
import { Link } from 'react-router'
import { Button, Icon, Loader } from 'semantic-ui-react'
import Griddle, { RowDefinition, ColumnDefinition } from 'griddle-react'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import statuses from 'helpers/userStatuses'
import { griddleSemanticStyle, EnhanceWithRowData, GriddleDateColumn } from 'helpers/griddleExtensions'

import FilterList from './FilterList'
import styles from './styles'


const ColumnUserName = EnhanceWithRowData(({ rowData }) => (
  <span>
    {sF('UserEdit')
      ? <Link to={`/users/edit/${rowData.id}`}>{rowData.name}</Link>
      : rowData.name
    }
  </span>
  ),
)

const ColumnRoles = EnhanceWithRowData(({ rowData }) => (
  <span>
    {rowData.roles.map(v => v.name).join(', ')}
  </span>
  ),
)

const ColumnStatus = localize => ({ value }) => (
  <span> {localize(statuses.filter(v => v.key === value)[0].value)}</span>
)

const ColumnActions = (localize, deleteUser) => EnhanceWithRowData(({ rowData }) => {
  const handleDelete = () => {
    const msg = `${localize('DeleteUserMessage')} '${rowData.name}'. ${localize('AreYouSure')}?`
    if (confirm(msg)) {
      deleteUser(rowData.id)
    }
  }
  return (
    <Button.Group>
      {sF('UserDelete') && <Button onClick={handleDelete} icon="delete" color="red" /> }
    </Button.Group>
  )
})

ColumnActions.propTypes = {
  localize: React.PropTypes.func.isRequired,
  deleteUser: React.PropTypes.func.isRequired,
}

class UsersList extends React.Component {
  componentDidMount() {
    const { filter } = this.props
    this.props.fetchUsers(filter)
  }

  onNext = () => {
    const { filter } = this.props
    this.props.fetchUsers({ ...filter, page: filter.page + 1 })
  }

  onPrevious = () => {
    const { filter } = this.props
    this.props.fetchUsers({ ...filter, page: filter.page - 1 })
  }

  onGetPage = (pageNumber) => {
    const { filter } = this.props
    this.props.fetchUsers({ ...filter, page: pageNumber })
  }

  onFilter = (data) => {
    const { filter } = this.props
    this.props.fetchUsers({ ...filter, ...data, page: 1 })
  }

  onSort = (sort) => {
    const { filter } = this.props
    switch (sort.id) {
      case 'name':
      case 'regionName':
      case 'creationDate':
        this.props.fetchUsers({
          ...filter,
          sortColumn: sort.id,
          sortAscending: filter.sortColumn !== sort.id || !filter.sortAscending,
        })
        break
      default:
        break
    }
  }

  render() {
    const { filter, users, totalCount, totalPages, editUser, deleteUser, status, localize } = this.props
    return (
      <div>
        <div className={styles['add-user']}>
          <h2>{localize('UsersList')}</h2>
          {sF('UserCreate')
            && <Button
              as={Link} to="/users/create"
              content={localize('CreateUserButton')}
              icon={<Icon size="large" name="user plus" />}
              size="medium"
              color="green"
            />}
        </div>
        <div className={styles['list-root']}>
          <Loader active={status === 1} />
          <div className={styles.addUser} />

          <FilterList onChange={this.onFilter} />

          <Griddle
            data={users}
            pageProperties={{
              currentPage: filter.page,
              pageSize: filter.pageSize,
              recordCount: totalCount,
            }}
            events={{
              onNext: this.onNext,
              onPrevious: this.onPrevious,
              onGetPage: this.onGetPage,
              onSort: this.onSort,
            }}
            components={{
              Filter: () => <span />,
              SettingsToggle: () => <span />,
            }}
            sortProperties={[{ id: filter.sortColumn, sortAscending: filter.sortAscending }]}
            styleConfig={griddleSemanticStyle}
          >
            <RowDefinition>
              <ColumnDefinition id="name" title={localize('UserName')} customComponent={ColumnUserName} width={150} />
              <ColumnDefinition id="description" title={localize('Description')} />
              <ColumnDefinition id="regionName" title={localize('Region')} width={200} />
              <ColumnDefinition id="roles" title={localize('Roles')} customComponent={ColumnRoles} width={200} />
              <ColumnDefinition id="creationDate" title={localize('RegistrationDate')} customComponent={GriddleDateColumn} width={150} />
              <ColumnDefinition id="status" title={localize('Status')} customComponent={ColumnStatus(localize)} width={100} />
              <ColumnDefinition title="&nbsp;" customComponent={ColumnActions(localize, deleteUser)} width={50} />
            </RowDefinition>
          </Griddle>
        </div>
      </div>
    )
  }
}

UsersList.propTypes = {
  localize: React.PropTypes.func.isRequired,
  fetchUsers: React.PropTypes.func.isRequired,
  filter: React.PropTypes.shape({
    page: React.PropTypes.number.isRequired,
    pageSize: React.PropTypes.number.isRequired,
  }).isRequired,
}

export default wrapper(UsersList)
