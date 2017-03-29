import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Search, Message, Icon, Loader } from 'semantic-ui-react'

import { internalRequest } from 'helpers/request'
import { wrapper } from 'helpers/locale'
import debounce from 'lodash/debounce'

const waitTime = 500
const { func } = React.PropTypes

class Edit extends React.Component {
  static propTypes = {
    editForm: func.isRequired,
    submitAddress: func.isRequired,
    localize: func.isRequired,
  }

  state = {
    data: {
      addressPart1: '',
      addressPart2: '',
      addressPart3: '',
      addressPart4: '',
      addressPart5: '',
      addressDetails: '',
      geographicalCodes: '',
      gpsCoordinates: '',
    },
    isLoading: false,
    searchResults: [],
    msgFailFetchSoates: undefined,
    msgFailFetchSoatesByCode: undefined,
  }

  componentDidMount() {
    this.fetchAddress(this.props.id)
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ data: { ...s.data, [name]: value } }))
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.submitAddress(this.state.data)
  }

  fetchAddress = (id) => {
    internalRequest({
      url: `/api/addresses/${id}`,
      method: 'get',
      onSuccess: (result) => {
        this.setState({ data: result })
      },
      onFail: () => {
        this.setState({
          addressFailMessage: 'failed loading addresses',
        })
      },
    })
  }

  handleDataAccessChange = ({ name, type }) => {
    const { data } = this.state
    const item = data.dataAccess[type].find(x => x.name === name)
    const items = data.dataAccess[type].filter(x => x.name !== name)
    this.props.editForm({
      name: 'dataAccess',
      value: { ...data.dataAccess, [type]: [...items, { ...item, allowed: !item.allowed }] },
    })
  }

  handleSoateEdit = (e, value) => {
    this.setState(s => (
      { data:
        { ...s.data, geographicalCodes: value },
        isLoading: true,
      }))
    debounce(() => internalRequest({
      url: '/api/soates',
      queryParams: { code: value, limit: 5 },
      method: 'get',
      onSuccess: (result) => {
        this.setState(s => ({ data: { ...s.data },
          isLoading: false,
          msgFailFetchSoatesByCode: undefined,
          searchResults: [...result.map(x => ({ title: x.code, description: x.name }))],
        }))
      },
      onFail: () => {
        this.setState(s => ({ data:
          { ...s.data },
          isLoading: false,
          searchResults: [],
          msgFailFetchSoatesByCode: 'Failed to fetch Soate Structure' }
        ))
      },
    }), waitTime)()
  }

  handleSearchResultSelect = (e, soate) => {
    e.preventDefault()
    internalRequest({
      url: `/api/soates/${soate.title}`,
      method: 'get',
      onSuccess: (result) => {
        const [addressPart1 = '', addressPart2 = '', addressPart3 = '', addressPart4 = '', addressPart5 = ''] = result
        this.setState(s => ({ data: {
          ...s.data,
          addressPart1,
          addressPart2,
          addressPart3,
          addressPart4,
          addressPart5 },
          isLoading: false,
          msgFailFetchSoates: undefined,
        }))
      },
      onFail: () => {
        this.setState(s => ({ data:
          { ...s.data },
          isLoading: false,
          msgFailFetchSoates: 'Failed to fetch Soate' }
          ))
      },
    })
    this.setState(s => ({ data: { ...s.data, geographicalCodes: soate.title } }))
  }

  renderForm() {
    const { localize } = this.props
    const { data, isLoading, searchResults, msgFailFetchSoates, msgFailFetchSoatesByCode } = this.state
    return (
      <div>
        <Form onSubmit={this.handleSubmit}>
          <h2>{localize('EditAddress')}</h2>
          <Form.Group widths="equal">
            <Form.Input
              name="addressPart1"
              value={data.addressPart1}
              label={`${localize('AddressPart')} 1`}
              placeholder={`${localize('AddressPart')} 1`}
              disabled
            />
            <Form.Input
              name="addressPart2"
              value={data.addressPart2}
              label={`${localize('AddressPart')} 2`}
              placeholder={`${localize('AddressPart')} 2`}
              disabled
            />
            <Form.Input
              name="addressPart3"
              value={data.addressPart3}
              label={`${localize('AddressPart')} 3`}
              placeholder={`${localize('AddressPart')} 3`}
              disabled
            />
          </Form.Group>
          <Form.Group widths="equal">
            <Form.Input
              name="addressPart4"
              value={data.addressPart4}
              label={`${localize('AddressPart')} 4`}
              placeholder={`${localize('AddressPart')} 4`}
              disabled
            />
            <Form.Input
              name="addressPart5"
              value={data.addressPart5}
              label={`${localize('AddressPart')} 5`}
              placeholder={`${localize('AddressPart')} 5`}
              disabled
            />
          </Form.Group>
          <Form.Group widths="equal">
            <Form.Field
              label={localize('GeographicalCodes')}
              control={Search}
              loading={isLoading}
              placeholder={localize('GeographicalCodes')}
              fluid
              onResultSelect={this.handleSearchResultSelect}
              onSearchChange={this.handleSoateEdit}
              results={searchResults}
              value={data.geographicalCodes}
              required
            />
            <Form.Input
              name="gpsCoordinates"
              value={data.gpsCoordinates}
              onChange={this.handleEdit}
              label={localize('GpsCoordinates')}
              placeholder={localize('GpsCoordinates')}
            />
          </Form.Group>
          <Form.Input
            name="addressDetails"
            value={data.addressDetails}
            onChange={this.handleEdit}
            label={localize('AddressDetails')}
            placeholder={localize('AddressDetails')}
          />
          {msgFailFetchSoates && <Message content={msgFailFetchSoates} negative />}
          {msgFailFetchSoatesByCode && <Message content={msgFailFetchSoatesByCode} negative />}
          <Button
            as={Link} to="/addresses"
            content={localize('Back')}
            icon={<Icon size="large" name="chevron left" />}
            size="small"
            color="grey"
            type="button"
          />
          <Button
            content={localize('EditButton')}
            type="submit"
            floated="right"
            primary
          />
        </Form>
      </div>
    )
  }

  render() {
    return (
      <div>
        {this.state.data !== undefined ? this.renderForm() : <Loader active />}
      </div>
    )
  }
}

export default wrapper(Edit)


