import React from 'react'
import { func, shape, arrayOf, number, string } from 'prop-types'
import { Grid, Input, Dropdown, Button, Segment, List } from 'semantic-ui-react'
import Dropzone from 'react-dropzone'

import styles from './styles.pcss'

class Upload extends React.Component {
  static propTypes = {
    dataSources: arrayOf(shape({
      id: number.isRequired,
      name: string.isRequired,
    })),
    uploadFile: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    dataSources: [],
  }

  state = {
    description: '',
    dataSourceId: undefined,
    accepted: [],
    isLoading: false,
  }

  handleDrop = (accepted) => {
    this.setState({ accepted })
  }

  handleEdit = prop => (_, { value }) => {
    this.setState({ [prop]: value })
  }

  handleSubmit = () => {
    const file = this.state.accepted[0]
    const formData = new FormData()
    formData.append('datafile', file, file.name)
    formData.append('DataSourceId', this.state.dataSourceId)
    formData.append('Description', this.state.description)

    this.setState({ isLoading: true }, () => {
      this.props.uploadFile(formData, () => {
        this.setState({ accepted: [], isLoading: false })
      })
    })
  }

  render() {
    const { localize, dataSources } = this.props
    const { dataSourceId, isLoading, description } = this.state
    const file = this.state.accepted[0]
    const canSubmit = file !== undefined && dataSourceId !== undefined
    const options = dataSources.map(x => ({ text: x.name, value: x.id }))
    return (
      <Segment loading={isLoading}>
        <Grid>
          <Grid.Row columns={2}>
            <Grid.Column width={6}>
              <Dropdown
                value={dataSourceId}
                onChange={this.handleEdit('dataSourceId')}
                options={options}
                placeholder={localize('SelectDataSource')}
                selection
                fluid
              />
            </Grid.Column>
            <Grid.Column width={10}>
              <Input
                value={description}
                onChange={this.handleEdit('description')}
                placeholder={localize('EnterDescription')}
                fluid
              />
            </Grid.Column>
          </Grid.Row>
          <Grid.Row columns={1}>
            <Grid.Column>
              <Dropzone
                ref={(dz) => {
                  this.dropzone = dz
                }}
                onDrop={this.handleDrop}
                className={styles['dz-container']}
                multiple={false}
              >
                {file === undefined ? (
                  <p>{localize('DropZoneLabel')}</p>
                ) : (
                  <List>
                    <List.Header content={localize('NextFilesReadyForUpload')} />
                    <List.Item key={file.name} className={styles['dz-list']}>
                      <List.Icon name="file text outline" />
                      <List.Content
                        header={file.name}
                        description={`${file.type} ${Math.ceil(file.size / 1024)}Kb`}
                      />
                    </List.Item>
                  </List>
                )}
                <p>{localize('OnlySupportedFormatsAllowed')}: CSV, TXT, XML</p>
              </Dropzone>
            </Grid.Column>
          </Grid.Row>
          <Grid.Row>
            <Grid.Column>
              <Button
                onClick={canSubmit ? this.handleSubmit : () => this.dropzone.open()}
                content={localize(canSubmit ? 'UpLoad' : 'SelectFile')}
                icon="upload"
                color={canSubmit ? 'green' : 'blue'}
              />
            </Grid.Column>
          </Grid.Row>
        </Grid>
      </Segment>
    )
  }
}

export default Upload
