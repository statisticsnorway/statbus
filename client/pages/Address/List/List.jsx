import React from 'react'
import { wrapper } from 'helpers/locale'
import { Button, Icon, Table, Loader, Menu } from 'semantic-ui-react'
import { Link } from 'react-router'

const { array, func, number } = React.PropTypes

class AddressList extends React.Component {
  static propTypes = {
    fetchAddressList: func.isRequired,
    totalPages: number.isRequired,
    currentPage: number.isRequired,
    addresses: array.isRequired,
    localize: func.isRequired,
  }

  componentDidMount() {
    this.props.fetchAddressList()
  }

  renderTable() {
    const { addresses, localize, currentPage, totalPages } = this.props
    return (
      <Table celled padded={false}>
        <Table.Header>
          <Table.Row>
            <Table.HeaderCell>{`${localize('AddressPart')} 1`}</Table.HeaderCell>
            <Table.HeaderCell>{localize('GeographicalCodes')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('AddressDetails')}</Table.HeaderCell>
            <Table.HeaderCell />
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {addresses.map(address => (<Table.Row>
            <Table.Cell>{address.addressPart1}</Table.Cell>
            <Table.Cell>{address.geographicalCodes}</Table.Cell>
            <Table.Cell>{address.addressDetails}</Table.Cell>
            <Table.Cell width={2}>
              <Button
                as={Link} icon="edit" to={`/addresses/edit/${address.id}`} size="small" color="orange"
              />
            </Table.Cell>
          </Table.Row>))}
        </Table.Body>
        <Table.Footer>
          <Table.Row>
            <Table.HeaderCell colSpan="4">
              <Menu floated="right" pagination>
                {currentPage !== 1 &&
                <Menu.Item as={Link} to={`/addresses?page=${currentPage}`}>1</Menu.Item>}
                {currentPage > 1 &&
                <Menu.Item as={Link} icon to={`/addresses?page=${currentPage - 1}`}>
                  <Icon name="left chevron" />
                </Menu.Item>}
                <Menu.Item as={Link} active>{currentPage}</Menu.Item>
                {currentPage < totalPages &&
                <Menu.Item as={Link} icon to={`/addresses?page=${currentPage + 1}`}>
                  <Icon name="right chevron" />
                </Menu.Item>}
                {currentPage !== totalPages &&
                <Menu.Item as={Link} to={`/addresses?page=${totalPages}`}>{totalPages}</Menu.Item>}
              </Menu>
            </Table.HeaderCell>
          </Table.Row>
        </Table.Footer>
      </Table>
    )
  }

  render() {
    const { localize, fetching } = this.props
    return (
      <div>
        <h2>{localize('AddressList')}</h2>
        <Button
          content={localize('CreateNew')}
          as={Link}
          icon="add"
          to="/addresses/create"
          size="small" color="green"
        />
        <div>
          <br />
          { !fetching ? this.renderTable() : <Loader active /> }
        </div>
      </div>
    )
  }
 }

export default wrapper(AddressList)
