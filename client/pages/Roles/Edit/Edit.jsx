import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Loader, Icon } from 'semantic-ui-react'

import DataAccess from 'components/DataAccess'
import FunctionalAttributes from 'components/FunctionalAttributes'

import rqst from 'helpers/request'
import { wrapper } from 'helpers/locale'
import styles from './styles'

const { func } = React.PropTypes

class Edit extends React.Component {

  static propTypes = {
    editForm: func.isRequired,
    fetchRole: func.isRequired,
    submitRole: func.isRequired,
    localize: func.isRequired,
  }

  state = {
    standardDataAccess: {
      localUnit: [],
      legalUnit: [],
      enterpriseGroup: [],
      enterpriseUnit: [],
    },
   
    fetchingStandardDataAccess: true,
  
    standardDataAccessMessage: undefined,
   
  }

  componentDidMount() {
    this.props.fetchRole(this.props.id)
    this.fetchStandardDataAccess(this.props.id)

  }

  fetchStandardDataAccess(roleId) {
    rqst({
      url: `/api/accessAttributes/dataAttributesByRole/${roleId}`,
      onSuccess: (result) => {
     
          standardDataAccess: result,
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
       
          standardDataAccessFailMessage: 'error while fetching standard data access',
          fetchingStandardDataAccess: false,
        }))
      },
    })
  }
  

  handleEdit = (e, { name, value }) => {
    this.props.editForm({ name, value })
  }

  handleDataAccessChange = (data) => {
    this.setState((s) => {
      const item = s.standardDataAccess[data.type].find(x => x.name == data.name)
      const items = s.standardDataAccess[data.type].filter(x => x.name != data.name)
      return ({
        standardDataAccess: { ...s.standardDataAccess, [data.type]: [...items, { ...item, allowed: !item.allowed }] }
      })
    })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.submitRole({
      ...this.props.role,
      dataAccess: this.state.standardDataAccess,
    })
  }

  render() {
    const { role, editForm, submitRole, localize } = this.props
    const handleSubmit = (e) => {
      e.preventDefault()
      submitRole({ ...role, dataAccess: this.state.standardDataAccess })
    }
    const handleChange = propName => (e) => { editForm({ propName, value: e.target.value }) }
    const handleSelect = (e, { name, value }) => { editForm({ propName: name, value }) }
    const handleDataAccessChange = (e) => {
      this.setState(s => {
        const item = this.state.standardDataAccess[e.type].find(x => x.name == e.name)
        const items = this.state.standardDataAccess[e.type].filter(x => x.name != e.name)
        return ({
          ...s,
          standardDataAccess: { ...s.standardDataAccess, [e.type]: [...items, { ...item, allowed: !item.allowed }] }
        })
      })
    }
    const handleAccessToSystemFunctionsChange = (e) => editForm({
      propName: 'accessToSystemFunctions',
      value: e.value
        ? [...role.accessToSystemFunctions, e.name]
        : role.accessToSystemFunctions.filter(x => x !== e.name)
    })

    return (
      <div className={styles.roleEdit}>
        {role === undefined
          ? <Loader active />
          : <Form className={styles.form} onSubmit={this.handleSubmit}>
            <h2>{localize('EditRole')}</h2>
            <Form.Input
              value={role.name}
              onChange={this.handleEdit}
              name="name"
              label={localize('RoleName')}
              placeholder={localize('WebSiteVisitor')}
            />
            <Form.Input
              value={role.description}
              onChange={this.handleEdit}
              name="description"
              label={localize('Description')}
              placeholder={localize('OrdinaryWebsiteUser')}
            />
            {fetchingStandardDataAccess
              ? <Loader content={localize('fetching standard data access')} />
              : <DataAccess
                dataAccess={this.state.standardDataAccess}
                label={localize('DataAccess')}
                onChange={this.handleDataAccessChange}
              />}
            <FunctionalAttributes
              label={localize('AccessToSystemFunctions')}
              accessToSystemFunctions={role.accessToSystemFunctions}
              onChange={handleAccessToSystemFunctionsChange}
            />
            <Button
              as={Link} to="/roles"
              content={localize('Back')}
              icon={<Icon size="large" name="chevron left" />}
              size="small"
              color="grey"
              type="button"
            />
          
            <Button
              content={localize('Submit')}
              className={styles.sybbtn}
              type="submit"
              primary
            />
          </Form>}
      </div>
    )
  }
}

export default wrapper(Edit)
