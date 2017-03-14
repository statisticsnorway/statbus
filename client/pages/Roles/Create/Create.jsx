import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Icon, Loader } from 'semantic-ui-react'

import FunctionalAttributes from 'components/FunctionalAttributes'
import DataAccess from 'components/DataAccess'
import rqst from 'helpers/request'
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
    rqst({
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
      onError: () => {
        this.setState(({
          standardDataAccessFailMessage: 'error while fetching standard data access',
          fetchingStandardDataAccess: false,
        }))
      },
    })
  }

  handleAccessToSystemFunctionsChange = (e) => {
    this.setState(s => ({
      ...s,
      data: {
        ...s.data,
        accessToSystemFunctions: e.value
          ? [...s.data.accessToSystemFunctions, e.name]
          : s.data.accessToSystemFunctions.filter(x => x !== e.name)
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
            placeholder={localize('WebSiteVisitor')}
            required
          />
          <Form.Input
            name="description"
            onChange={this.handleEdit}
            value={data.description}
            label={localize('Description')}
            placeholder={localize('OrdinaryWebsiteUser')}
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
            accessToSystemFunctions={this.state.data.accessToSystemFunctions}
            onChange={this.handleAccessToSystemFunctionsChange}
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
