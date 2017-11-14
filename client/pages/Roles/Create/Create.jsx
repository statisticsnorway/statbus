import React from 'react'
import { func } from 'prop-types'
import { Button, Form, Icon, Loader } from 'semantic-ui-react'
import { equals } from 'ramda'

import FunctionalAttributes from 'components/FunctionalAttributes'
import DataAccess from 'components/DataAccess'
import ActivityTree from 'components/ActivityTree'
import { internalRequest } from 'helpers/request'
import styles from './styles.pcss'

class CreateForm extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    submitRole: func.isRequired,
    navigateBack: func.isRequired,
  }

  state = {
    data: {
      name: '',
      description: '',
      accessToSystemFunctions: [],
      standardDataAccess: {
        localUnit: [],
        legalUnit: [],
        enterpriseGroup: [],
        enterpriseUnit: [],
      },
      activiyCategoryIds: [],
    },
    activityTree: undefined,
    fetchingStandardDataAccess: true,
    standardDataAccessMessage: undefined,
  }

  componentDidMount() {
    this.fetchActivityTree()
    this.fetchStandardDataAccess()
  }

  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !equals(this.props, nextProps) ||
      !equals(this.state, nextState)
    )
  }

  setActivities = (activities) => {
    this.setState(s => ({
      data: { ...s.data, activiyCategoryIds: activities.filter(x => x !== 'all') },
    }))
  }

  fetchStandardDataAccess() {
    internalRequest({
      url: '/api/accessAttributes/dataAttributes',
      onSuccess: (result) => {
        this.setState(s => ({
          data: { ...s.data, standardDataAccess: result },
          fetchingStandardDataAccess: false,
        }))
      },
      onFail: () => {
        this.setState({
          standardDataAccessMessage: 'failed loading standard data access',
          fetchingStandardDataAccess: false,
        })
      },
    })
  }

  fetchActivityTree = () =>
    internalRequest({
      url: '/api/roles/fetchActivityTree',
      onSuccess: (activityTree) => {
        this.setState({ activityTree })
      },
    })

  handleAccessToSystemFunctionsChange = (data) => {
    this.setState(s => ({
      ...s,
      data: {
        ...s.data,
        [data.name]: data.checked
          ? [...s.data.accessToSystemFunctions, data.value]
          : s.data.accessToSystemFunctions.filter(x => x !== data.value),
      },
    }))
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ data: { ...s.data, [name]: value } }))
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.submitRole(this.state.data)
  }

  render() {
    const { localize, navigateBack } = this.props
    const { data, fetchingStandardDataAccess, activityTree } = this.state

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
          {fetchingStandardDataAccess ? (
            <Loader />
          ) : (
            <DataAccess
              value={data.standardDataAccess}
              name="standardDataAccess"
              label={localize('DataAccess')}
              onChange={this.handleEdit}
              localize={localize}
            />
          )}
          {activityTree && (
            <ActivityTree
              name="activiyCategoryIds"
              label="ActivityCategoryLookup"
              dataTree={activityTree}
              checked={this.state.data.activiyCategoryIds}
              callBack={this.setActivities}
              localize={localize}
            />
          )}
          <FunctionalAttributes
            label={localize('AccessToSystemFunctions')}
            value={this.state.data.accessToSystemFunctions}
            onChange={this.handleAccessToSystemFunctionsChange}
            name="accessToSystemFunctions"
            localize={localize}
          />
          <Button
            content={localize('Back')}
            onClick={navigateBack}
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

export default CreateForm
