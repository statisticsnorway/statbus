import React from 'react'
import { func, bool, shape, number, arrayOf } from 'prop-types'
import { Link } from 'react-router'
import { Table, Icon, Segment, Pagination, Button } from 'semantic-ui-react'
import { equals } from 'ramda'

import { checkSystemFunction as sF } from '/helpers/config'
import FilterList from './FilterList.jsx'
import ListItem from './ListItem.jsx'
import styles from './styles.scss'

class UsersList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    fetchUsers: func.isRequired,
    isLoading: bool.isRequired,
    allRegions: shape({}).isRequired,
    totalPages: number.isRequired,
    filter: shape({
      page: number.isRequired,
      pageSize: number.isRequired,
    }).isRequired,
    users: arrayOf(shape({})).isRequired,
    setUserStatus: func.isRequired,
  }

  state = {
    activePage: this.props.filter.page,
  }

  componentDidMount() {
    const { filter } = this.props
    this.props.fetchUsers({ ...filter, status: 2 })
  }

  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !equals(this.props, nextProps) ||
      !equals(this.state, nextState)
    )
  }

  onFilter = (data) => {
    const { filter } = this.props
    this.props.fetchUsers({ ...filter, ...data, page: 1 })
  }

  onSort = sort => () => {
    const { filter, fetchUsers } = this.props
    switch (sort) {
      case 'name':
      case 'creationDate':
      case 'description':
      case 'status':
        fetchUsers({
          ...filter,
          sortBy: sort,
          sortAscending: !filter.sortAscending,
        })
        break
      default:
        break
    }
  }

  handlePaginationChange = (e, { activePage }) => {
    const { filter } = this.props
    this.props.fetchUsers({ ...filter, page: activePage })
  }

  render() {
    const { filter, users, totalPages, allRegions, setUserStatus, isLoading, localize } = this.props
    const checkSorting = () => (filter.sortAscending ? 'ascending' : 'descending')
    const defaultSorting = () =>
      filter.sortAscending === undefined || !filter.sortAscending ? 'ascending' : 'descending'
    return (
      <div>
        <div className={styles['add-user']}>
          <h2>{localize('UsersList')}</h2>
          {sF('UserCreate') && (
            <Button
              as={Link}
              to="/users/create"
              content={localize('CreateUserButton')}
              icon={<Icon size="large" name="user plus" />}
              size="medium"
              color="green"
            />
          )}
        </div>
        <br />
        <div className={styles['list-root']}>
          <div className={styles.addUser} />
          <FilterList onChange={this.onFilter} filter={filter} localize={localize} />
          <Segment vertical loading={isLoading}>
            <Table sortable padded size="small" fixed singleLine className="wrap-content">
              <Table.Header>
                <Table.Row>
                  <Table.HeaderCell
                    textAlign="center"
                    sorted={filter.sortBy === 'name' ? checkSorting() : null}
                    onClick={this.onSort('name')}
                    content={localize('UserName')}
                  />
                  <Table.HeaderCell
                    textAlign="center"
                    sorted={filter.sortBy === 'description' ? checkSorting() : null}
                    onClick={this.onSort('description')}
                    content={localize('Description')}
                  />
                  <Table.HeaderCell textAlign="center" content={localize('Roles')} />
                  <Table.HeaderCell
                    textAlign="center"
                    sorted={filter.sortBy === 'creationDate' ? checkSorting() : null}
                    onClick={this.onSort('creationDate')}
                    content={localize('RegistrationDate')}
                  />
                  <Table.HeaderCell
                    textAlign="center"
                    sorted={filter.sortBy === 'status' ? defaultSorting() : null}
                    onClick={this.onSort('status')}
                    content={localize('Status')}
                  />
                  <Table.HeaderCell textAlign="center" content={localize('Regions')} />
                  <Table.HeaderCell />
                </Table.Row>
              </Table.Header>
              <Table.Body>
                {users.map(user => (
                  <ListItem
                    key={user.id}
                    localize={localize}
                    regionsTree={allRegions}
                    setUserStatus={setUserStatus}
                    getFilter={() => this.props.filter}
                    {...user}
                  />
                ))}
              </Table.Body>
            </Table>
            <div className={styles.paginationContainer}>
              <Pagination
                activePage={filter.page}
                onPageChange={this.handlePaginationChange}
                totalPages={totalPages}
                boundaryRange={1}
                siblingRange={3}
                size="large"
              />
            </div>
          </Segment>
        </div>
      </div>
    )
  }
}

export default UsersList
