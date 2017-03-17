import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Icon, Loader } from 'semantic-ui-react'

import FunctionalAttributes from 'components/FunctionalAttributes'
import DataAccess from 'components/DataAccess'
import { internalRequest } from 'helpers/request'
import { wrapper } from 'helpers/locale'
import styles from './styles'

const { func } = React.PropTypes

class CreateForm extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    submitRole: func.isRequired,
  }

  state = {
    data: {
      name: '',
      description: '',
      accessToSystemFunctions: [],
      dataAccess: {
        localUnit: [],
        legalUnit: [],
        enterpriseGroup: [],
        enterpriseUnit: [],
      },
    },
    fetchingStandardDataAccess: true,
    standardDataAccessMessage: undefined,
  }

  componentDidMount() {
    this.fetchStandardDataAccess()
  }

  fetchStandardDataAccess() {
    internalRequest({
      url: '/api/accessAttributes/dataAttributes',
      onSuccess: (result) => {
        this.setState(s => ({
          data: { ...s.data, dataAccess: result },
          fetchingStandardDataAccess: false,
        }))
      },
      onFail: () => {
        this.setState(({
          standardDataAccessMessage: 'failed loading standard data access',
          fetchingStandardDataAccess: false,
        }))
      },
    })
  }

  handleAccessToSystemFunctionsChange = (data) => {
    this.setState(s => ({
      ...s,
      data: {
        ...s.data,
        [data.name]: data.checked
          ? [...s.data.accessToSystemFunctions, data.value]
          : s.data.accessToSystemFunctions.filter(x => x !== data.value)
      }

    }))
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ data: { ...s.data, [name]: value } }))
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.submitRole(this.state.data)
  }

  handleDataAccessChange = ({ name, type }) => {
    this.setState((s) => {
      const item = s.data.dataAccess[type].find(x => x.name === name)
      const items = [
        ...s.data.dataAccess[type].filter(x => x.name !== name),
        { ...item, allowed: !item.allowed },
      ]
      return { data: { ...s.data, dataAccess: { ...s.data.dataAccess, [type]: items } } }
    })
  }

  render() {
    const { submitRole, localize } = this.props
    const { data, fetchingStandardDataAccess } = this.state

    return (
      <div className={styles.rolecreate}>
        <Form className={styles.form} onSubmit={this.handleSubmit}>
          <h2>{localize('CreateNewRole')}</h2>
          <Form.Input
            name="name"
            onChange={this.handleEdit}
            value={data.name}
            label={localize('RoleName')}
            placeholder={localize('RoleNamePlaceholder')}
            required
          />
          <Form.Input
            name="description"
            onChange={this.handleEdit}
            value={data.description}
            label={localize('Description')}
            placeholder={localize('RoleDescriptionPlaceholder')}
            required
          />
          {fetchingStandardDataAccess
            ? <Loader content="fetching standard data access" />
            : <DataAccess
              dataAccess={data.dataAccess}
              label={localize('DataAccess')}
              onChange={this.handleDataAccessChange}
            />}
          <FunctionalAttributes
            label={localize('AccessToSystemFunctions')}
            value={this.state.data.accessToSystemFunctions}
            onChange={this.handleAccessToSystemFunctionsChange}
            name="accessToSystemFunctions"
          />
          <Button
            as={Link} to="/roles"
            content={localize('Back')}
            icon={<Icon size="large" name="chevron left" />}
            size="small"
            color="grey"
            type="button"
          />

          <Button className={styles.sybbtn} type="submit" primary>
            {localize('Submit')}
          </Button>
        </Form>
      </div>
    )
  }
}

export default wrapper(CreateForm)
